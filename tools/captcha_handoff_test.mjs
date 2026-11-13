import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';

const script = readFileSync(new URL('../src/browser_helper/captcha.js', import.meta.url), 'utf8');
const seek = (token = '', game = 'FRA:fixture') =>
    `https://matchmaker.krunker.io/seek-game?game=${encodeURIComponent(game)}${token ? '&captchaToken=' + encodeURIComponent(token) : ''}`;
function page({origin = 'https://krunker.io', frame = false, fetchResponse = 'fixture-response', username = 'fixture-account'} = {}) {
    const sent = [];
    class XHR extends EventTarget {
        constructor() { super(); this.readyState = 1; this.status = 200; this.responseType = ''; this.responseText = ''; this.aborted = false; }
        open(method, url) { this.url = url; }
        emit(name) { this.dispatchEvent(new Event(name)); }
        abort() { this.aborted = true; }
        send(body) { sent.push(['xhr', this.url, body]); }
    }
    class WS { constructor(url) { this.url = url; sent.push(['ws', url]); } close(code, reason) { this.closed = [code, reason]; } }
    const context = vm.createContext({URL, Promise, WeakMap, Proxy, Reflect, DOMException,
        location: {origin, href: origin + '/'}, XMLHttpRequest: XHR, WebSocket: WS,
        localStorage: {getItem: key => key === 'krunker_username' ? username : null},
        fetch: (...args) => { sent.push(['fetch', ...args]); return Promise.resolve(typeof fetchResponse === 'function' ? fetchResponse(...args) : fetchResponse); },
        __krodinCaptchaGame: 'FRA:fixture'});
    context.window = context;
    context.top = frame ? {} : context;
    vm.runInContext(script, context);
    return {context, sent};
}
for (const kind of ['fetch', 'xhr']) {
    const {context: c, sent} = page();
    const request = url => {
        if (kind === 'fetch') return c.fetch(url);
        const xhr = new c.XMLHttpRequest(); xhr.open('GET', url); xhr.send(); return xhr;
    };
    request(seek());
    assert.equal(sent.length, 1, 'initial native-equivalent page request proceeds to trigger challenge');
    const provisional = new c.WebSocket('wss://lobby-fixture.frankfurt.krunker.io/ws?gameId=FRA:fixture');
    assert.equal(sent.length, 2, 'the provisional socket may trigger the official challenge flow');
    assert.equal(c.__krodinCaptchaHandoff.sockets.length, 1);
    request(seek('fixture-proof+/='));
    assert.equal(sent.length, 2, 'proof must not be consumed by a browser request');
    assert.equal(c.__krodinCaptchaHandoff.state, 'CAPTCHA_READY');
    assert.equal(c.__krodinCaptchaHandoff.token, 'fixture-proof+/=');
    assert.equal(c.__krodinCaptchaHandoff.sockets.length, 0, 'provisional browser sockets close when proof is captured');
    assert.deepEqual(provisional.closed, [1000, 'native client owns the game connection']);
    request(seek('later-proof'));
    assert.equal(c.__krodinCaptchaHandoff.token, 'fixture-proof+/=', 'first proof remains stable until private handoff');
    assert.throws(() => new c.WebSocket('wss://lobby-fixture.frankfurt.krunker.io/ws?gameId=FRA:fixture'), /native client/);
    vm.runInContext(script, c);
    assert.equal(c.__krodinCaptchaHandoff.token, 'fixture-proof+/=', 'installation is idempotent');
}
{
    const {context: c, sent} = page();
    c.fetch(seek('wrong-invite-proof', 'NY:other'));
    assert.equal(c.__krodinCaptchaHandoff.state, 'CAPTCHA_WRONG_INVITE');
    assert.equal(c.__krodinCaptchaHandoff.token, '');
    assert.equal(sent.length, 0);
}
{
    const {context: c, sent} = page();
    c.fetch('https://other.invalid/seek-game?captchaToken=unrelated');
    new c.WebSocket('wss://other.invalid/events');
    assert.equal(sent.length, 2);
    const provisional = new c.WebSocket('wss://lobby-fixture.krunker.io/ws');
    assert.equal(c.__krodinCaptchaHandoff.state, 'WAIT_CAPTCHA');
    assert.equal(c.__krodinCaptchaHandoff.sockets.length, 1);
    assert.equal(c.__krodinCaptchaHandoff.state, 'WAIT_CAPTCHA', 'an early browser socket must not end the proof wait');
}
for (const proof of ['bad proof', 'x'.repeat(16385)]) {
    const {context: c, sent} = page();
    c.fetch(seek(proof));
    assert.equal(c.__krodinCaptchaHandoff.state, 'CAPTCHA_BAD_TOKEN');
    assert.equal(sent.length, 0);
}
for (const options of [{origin: 'https://other.invalid'}, {frame: true}]) {
    const {context: c, sent} = page(options);
    c.fetch(seek('fixture-proof'));
    assert.equal(c.__krodinCaptchaHandoff, undefined);
    assert.equal(sent.length, 1);
}
const assignment = {host: 'lobby-fixture.krunker.io', port: 3000, clientId: 'fixture-client', gameId: 'FRA:assigned'};
const intendedSocket = 'wss://lobby-fixture.krunker.io/ws?gameId=FRA:assigned&clientKey=fixture-client&clientUID=fixture-uid&at=fresh-sdk-token&tc=fixture-tc&dm=fixture-dm&bpt=fixture-bypass';
const response = {ok: true, clone() { return {json: async () => assignment}; }};
const assertHandoff = (c, sent) => {
    assert.equal(c.__krodinCaptchaHandoff.state, 'CAPTCHA_ASSIGNMENT');
    const captured = JSON.parse(c.__krodinCaptchaHandoff.assignment);
    assert.equal(captured.websocketUrl, intendedSocket, 'preserve fresh SDK access and every optional parameter exactly');
    assert.equal(captured.usernamePresent, true);
    assert.equal(captured.gameId, 'FRA:assigned', 'a reassigned region is allowed');
    assert.equal(sent.filter(([kind]) => kind === 'ws').length, 0, 'the underlying browser constructor must never receive the assigned socket');
    assert.throws(() => new c.WebSocket(intendedSocket), /native client/);
};
{
    const {context: c, sent} = page({fetchResponse: response});
    assert.equal(await c.fetch(seek()), response, 'official page receives assignment to select its final SDK token');
    assert.equal(c.__krodinCaptchaHandoff.state, 'WAIT_SOCKET_INTENT');
    assert.equal(c.__krodinCaptchaHandoff.assignment, '', 'HTTP assignment alone must not start a native connection');
    assert.throws(() => new c.WebSocket(intendedSocket), /native client/);
    assertHandoff(c, sent);
}
for (const event of ['readystatechange', 'load']) {
    for (const responseType of ['', 'json']) {
        const {context: c, sent} = page();
        const xhr = new c.XMLHttpRequest();
        let pageRan = false;
        // Page listener deliberately installed before open/send; no abort or
        // fictional DOM event cancellation is needed to prevent a browser socket.
        xhr.addEventListener(event, () => {
            pageRan = true;
            assert.throws(() => new c.WebSocket(intendedSocket), /native client/);
        });
        xhr.open('GET', seek()); xhr.send();
        xhr.responseType = responseType;
        xhr.response = assignment; xhr.responseText = JSON.stringify(assignment); xhr.readyState = 4;
        xhr.emit(event);
        assert.equal(pageRan, true);
        assert.equal(xhr.aborted, false);
        assertHandoff(c, sent);
    }
}
for (const [options, socket, state] of [
    [{username: '   '}, intendedSocket, 'CAPTCHA_LOGIN_REQUIRED'],
    [{}, intendedSocket.replace('fresh-sdk-token', ''), 'CAPTCHA_BAD_TOKEN'],
    [{}, intendedSocket.replace('fixture-client', 'wrong-client'), 'CAPTCHA_SOCKET_MISMATCH'],
    [{}, intendedSocket.replace('FRA:assigned', 'NY:wrong'), 'CAPTCHA_SOCKET_MISMATCH'],
]) {
    const {context: c, sent} = page({...options, fetchResponse: response});
    await c.fetch(seek());
    assert.throws(() => new c.WebSocket(socket), /native client/);
    assert.equal(c.__krodinCaptchaHandoff.state, state);
    assert.equal(c.__krodinCaptchaHandoff.assignment, '');
    assert.equal(sent.filter(([kind]) => kind === 'ws').length, 0);
}
{
    const {context: c} = page({fetchResponse: {ok: false}});
    const errorResponse = await c.fetch(seek());
    assert.equal(errorResponse.ok, false, 'matchmaking failures still reach the official challenge flow');
    assert.equal(c.__krodinCaptchaHandoff.state, 'WAIT_CAPTCHA');
}
console.log('Challenge handoff: proof interception, exact socket intent, fresh SDK token, optional parameters, real event ordering, invite and login gates passed.');
