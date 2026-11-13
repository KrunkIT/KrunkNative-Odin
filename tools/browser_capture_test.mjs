import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';

const auth = readFileSync(new URL('../src/browser_helper/auth.js', import.meta.url), 'utf8');
const tokenKey = '__FRVR_auth_access_token';
const usernameKey = 'krunker_username';
const now = 1794350000000;
const jwt = (exp = Math.floor(now / 1000) + 3600, claims = {}) =>
    `eyJhbGciOiJub25lIn0.${Buffer.from(JSON.stringify({exp, ...claims})).toString('base64url')}.fixture`;
const flush = async () => { for (let i = 0; i < 8; i++) await Promise.resolve(); };

function page({origin = 'https://krunker.io', frame = false, values = {}} = {}) {
    const storage = new Map(Object.entries(values));
    const reads = [];
    let clock = now;
    const context = vm.createContext({
        Promise, Date: {now: () => clock}, atob,
        location: {origin},
        localStorage: {getItem: key => { reads.push(key); return storage.get(key) ?? null; }},
    });
    context.window = context;
    context.top = frame ? {} : context;
    const poll = () => vm.runInContext(auth, context);
    const advance = ms => { clock += ms; };
    const settle = () => { poll(); advance(1000); return poll(); };
    return {context, storage, reads, poll, advance, settle};
}

// Anonymous tokens must not even be read, including when the SDK could return one.
for (const username of [undefined, '', '   ']) {
    const {context, reads, poll} = page({values: {[tokenKey]: jwt(), ...(username === undefined ? {} : {[usernameKey]: username})}});
    context.FRVR = {auth: {getFreshAccessToken: () => { throw new Error('must not request an anonymous token'); }}};
    assert.equal(poll().state, 'WAIT_LOGIN');
    assert.deepEqual(reads, [usernameKey]);
}

// Username can precede the account token: do not read the old token during the grace period.
{
    const {storage, reads, poll, advance} = page({values: {[tokenKey]: jwt(), refresh_token: 'fixture-refresh'}});
    assert.equal(poll().state, 'WAIT_LOGIN');
    storage.set(usernameKey, 'FixtureUser');
    assert.equal(poll().state, 'WAIT_STORAGE');
    advance(999);
    assert.equal(poll().state, 'WAIT_STORAGE');
    assert.equal(reads.includes(tokenKey), false);
    const accountToken = jwt(Math.floor(now / 1000) + 7200);
    storage.set(tokenKey, accountToken);
    advance(1);
    const result = poll();
    assert.equal(result.state, 'READY');
    assert.equal(result.token, accountToken);
    assert.equal(JSON.stringify(result).includes('FixtureUser'), false);
    assert.equal(JSON.stringify(result).includes('fixture-refresh'), false);
    storage.delete(usernameKey);
    assert.equal(poll().state, 'WAIT_LOGIN');
    storage.set(usernameKey, 'FixtureUser');
    assert.equal(poll().state, 'WAIT_STORAGE');
    advance(1000);
    assert.equal(poll().state, 'READY');
    storage.set(usernameKey, 'DifferentFixtureUser');
    assert.equal(poll().state, 'WAIT_STORAGE');
    advance(999);
    assert.equal(poll().state, 'WAIT_STORAGE');
    advance(1);
    assert.equal(poll().state, 'READY');
}

for (const options of [{origin: 'https://evil.invalid'}, {origin: 'http://krunker.io'}, {frame: true}]) {
    const {reads, poll} = page({...options, values: {[tokenKey]: jwt(), [usernameKey]: 'FixtureUser'}});
    assert.equal(poll().state, 'OTHER_ORIGIN');
    assert.equal(reads.length, 0);
}
{
    const {context, reads, poll} = page({values: {[tokenKey]: jwt(), [usernameKey]: 'FixtureUser'}});
    context.__krodinProbeOnly = true;
    context.FRVR = {auth: {getFreshAccessToken: () => { throw new Error('probe must not request access'); }}};
    assert.equal(poll().state, 'SDK_AVAILABLE');
    assert.equal(poll().token, undefined);
    assert.equal(reads.length, 0);
}
{
    const {context, poll} = page();
    context.localStorage.getItem = () => { throw new Error('secret storage exception'); };
    const result = poll();
    assert.equal(result.state, 'STORAGE_UNAVAILABLE');
    assert.equal(JSON.stringify(result).includes('secret'), false);
}

// Expiry checks must never forward missing, malformed, or expiring access tokens.
for (const token of [undefined, '', 'opaque', 'a.%%%.c', jwt('4102444800'), jwt(null), jwt(1794350060), jwt(1794350061), jwt(1794350000), 'x'.repeat(32769)]) {
    const {poll, settle} = page({values: {[usernameKey]: 'FixtureUser', ...(token === undefined ? {} : {[tokenKey]: token})}});
    assert.equal(settle().state, 'WAIT_SDK');
    assert.equal(poll().token, undefined);
}
assert.equal(page({values: {[usernameKey]: 'FixtureUser', [tokenKey]: jwt(1794350062)}}).settle().state, 'READY');

// A username flag and verified=true do not turn a guest JWT into account access.
for (const claims of [
    {extra: {identifier: 'fixture-id', platform: 'anonymous', verified: true}, iss: 'FRVR', sub: 'fixture-subject'},
    {platform: 'anon'},
    {extra: {nested: [{platform: ' ANONYMOUS '}]}},
    {extra: {platform: 'username'}, other: {Platform: 'Anon'}},
]) {
    const guest = jwt(undefined, claims);
    const {context, storage, poll, advance, settle} = page({values: {[usernameKey]: 'FixtureUser', [tokenKey]: guest}});
    context.FRVR = {auth: {getFreshAccessToken: () => { throw new Error('must wait for account login instead of renewing a guest'); }}};
    const result = settle();
    assert.equal(result.state, 'GUEST_TOKEN');
    assert.equal(result.token, undefined);
    assert.equal(JSON.stringify(result).includes('fixture-id'), false);
    advance(5000);
    assert.equal(poll().state, 'GUEST_TOKEN');
    const account = jwt(undefined, {extra: {platform: 'username', verified: true}});
    storage.set(tokenKey, account);
    assert.equal(poll().token, account);
    storage.delete(usernameKey);
    assert.equal(poll().state, 'WAIT_LOGIN');
}
for (const claims of [{extra: {platform: 'username'}}, {extra: {platform: 'anonymously'}}, {extra: {description: 'anonymous', platform: null}}]) {
    const {settle} = page({values: {[usernameKey]: 'FixtureUser', [tokenKey]: jwt(undefined, claims)}});
    assert.equal(settle().state, 'READY');
}

// SDK return values are ignored; storage under a current username supplies native access.
{
    const {context, storage, poll, advance, settle} = page({values: {[usernameKey]: 'FixtureUser', [tokenKey]: jwt(1)}});
    let calls = 0;
    context.FRVR = {auth: {getFreshAccessToken: async () => { calls++; return 'sdk-return-must-not-be-forwarded'; }}};
    assert.equal(settle().state, 'PENDING');
    await flush();
    assert.equal(poll().state, 'WAIT_STORAGE');
    advance(1000);
    assert.equal(poll().state, 'WAIT_TOKEN');
    assert.equal(poll().token, undefined);
    assert.equal(calls, 1);
    storage.set(tokenKey, jwt());
    assert.equal(poll().token, jwt());
    storage.delete(usernameKey);
    assert.equal(poll().state, 'WAIT_LOGIN');
}
{
    const {context, storage, reads, poll, advance, settle} = page({values: {[usernameKey]: 'FixtureUser'}});
    context.FRVR = {auth: {getFreshAccessToken: async () => { storage.set(tokenKey, jwt()); return jwt(); }}};
    settle(); await flush();
    reads.length = 0;
    assert.equal(poll().state, 'WAIT_STORAGE');
    advance(999);
    assert.equal(poll().state, 'WAIT_STORAGE');
    assert.equal(reads.includes(tokenKey), false);
    advance(1);
    assert.equal(poll().state, 'READY');
}
{
    const {context, poll, settle} = page({values: {[usernameKey]: 'FixtureUser'}});
    context.FRVR = {auth: {getFreshAccessToken: async () => { throw new Error('secret SDK details'); }}};
    settle(); await flush();
    const result = poll();
    assert.equal(result.state, 'SESSION_REJECTED');
    assert.equal(JSON.stringify(result).includes('secret'), false);
}
// Clearing the username while a renewal is pending must revoke the old settling state.
{
    const {context, storage, poll, advance, settle} = page({values: {[usernameKey]: 'FixtureUser'}});
    let finish;
    context.FRVR = {auth: {getFreshAccessToken: () => new Promise(resolve => { finish = resolve; })}};
    assert.equal(settle().state, 'PENDING');
    await flush();
    storage.delete(usernameKey);
    assert.equal(poll().state, 'WAIT_LOGIN');
    finish(); await flush();
    storage.set(usernameKey, 'DifferentFixtureUser');
    storage.set(tokenKey, jwt());
    assert.equal(poll().state, 'WAIT_STORAGE');
    advance(1000);
    assert.equal(poll().state, 'READY');
}
console.log('LocalStorage username gate, one-second settling, guest JWT rejection, account token capture, expiry, origin, and SDK renewal checks passed.');
