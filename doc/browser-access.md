# Windows browser access

`build.bat client none` builds the client and the Odin WebView2 helper. The official
Microsoft loader, license, and notices are restored by `tools/setup-webview2.ps1`
from a pinned NuGet package with SHA-256 verification. These files are included by
`package-windows.ps1`. The installed Evergreen runtime supplies the browser engine.

The helper runs in a separate process with two private inherited pipes. Inheritance
is restricted to those pipe ends. JSON lines carry request IDs, status codes,
access tokens, challenge proofs, and cancellation; frames are bounded to 64 KiB. No token appears in
arguments, diagnostic output, or menu views. Cancelling revokes the parent's request
before closing its pipes. The helper closes WebView2 when it sees cancellation or EOF.

WebView2 polls localStorage in the official top-level page. Every poll first checks
for a nonempty, non-whitespace `krunker_username`. Without it, the helper does not
read `__FRVR_auth_access_token` or request SDK access. When the username flag first
appears or changes, the helper waits one second before reading the token so the
site's login handler can replace anonymous access. The wait resets if the username
disappears. SDK renewal completion also starts a one-second storage wait. Both
waits keep the helper's event loop responsive to cancellation. After settling,
a usable access token under that exact key can pass to the native client. Its
decoded JWT payload must not contain a `platform` field equal to `anonymous` or
`anon` in any nested object or array (case-insensitive, surrounding whitespace
ignored). `verified: true` does not override a guest platform. A guest token keeps
the browser visible and waits for an account token instead of refreshing guest
access. Native checks apply the same exclusion to helper replies, memory, the
encrypted cache, and the fallback used on other platforms. Decoding does not verify the JWT
signature; server acceptance remains authoritative. Payloads are never logged. Login
credentials are entered directly into the official page; login response bodies
are not intercepted. Refresh credentials remain within the site's browser profile.

First access waits for this interactive login. A marker in the private browser
profile records successful access. If the username exists but stored access is
missing, malformed, or expiring, renewal calls `FRVR.auth.getFreshAccessToken()` on
the official page. The SDK return value is ignored: subsequent polls must still
read the localStorage access token while the username flag exists. The helper never implements
login/refresh endpoints. Script results are accepted only from the official
top-level origin and only if no navigation occurred during execution. Login popups
open in the same browser window so redirects remain visible to the user.

The access cache uses Windows DPAPI for the current user at
`%LOCALAPPDATA%\Krodin\access-account.dpapi`. Older `access.dpapi` caches are ignored
because they predate the username gate; Forget removes both cache names.
Unknown or malformed JWT
expiry triggers renewal. **Login** opens a visible browser without requiring an
invite, then caches access without connecting or leaving the current session.
**Join** reuses that access or starts login and continues the pending invite.
Startup never launches the helper. An established game connection has no expiry timer.
For this Windows test build, environment/`.env` token loading is disabled: only
browser access or its encrypted cache can resolve lobby invites. A fixed console
message confirms that fallback is disabled when browser access is unavailable.
Non-Windows clients keep their existing environment/`.env` method.

A browser access JWT does not complete a matchmaker CAPTCHA. A Windows
`/seek-game` response containing `CaptchaRequired` starts an experimental challenge
handoff, keeping the access JWT and original invite. The helper reuses the login
profile and installs `captcha.js` with WebView2's document-created script API before
navigating to that invite. The official page performs its challenge normally.
Fetch and XHR interception hold its first `seek-game` request with a `captchaToken`
for the exact invite, so the browser cannot consume the proof. A successful
assignment without a captcha token is observed as well. The page receives that
response, runs its normal SDK token selection, and constructs its gameplay socket
URL. The helper intercepts the WebSocket constructor before the underlying browser
socket opens. It hands off that exact URL, including the page's selected access
token and optional `clientUID`, `bpt`, `tc`, and `dm` parameters. Native checks
require a nonempty browser username, a usable non-guest JWT, a secure official
lobby host, and matching assignment game/client IDs. It rejects ambiguous query
parameters. This avoids rebuilding the URL with an older native cached token.
XHR responses are inspected at socket construction, so page event-handler order
cannot race an abort-based capture. Provisional sockets that preceded assignment
are closed when either handoff is ready. No game socket is relayed.

Native polling accepts the proof or assignment only from the official top-level
document with the current navigation/request ID. It closes the helper and
either retries native matchmaking with a fresh validation token and the
captured proof or continues directly with the captured assignment. Proofs are
memory-only and consumed by one native attempt; assignments are consumed by
one native WebSocket connection. Neither is cached or displayed. The browser-selected
account token updates the DPAPI access cache after native validation.
Both raw and URL-encoded values are redacted from diagnostics. Successful
matchmaking continues through the existing libcurl WebSocket. A repeated challenge,
helper failure, wrong invite, cancellation, or timeout stops the attempt. The
normal production assignment host uses the secure endpoint without appending
the matchmaker's internal `port: 3000`; IP-style assignments may retain an
explicit port. Non-Windows behavior is unchanged.
CAPTCHAs on `/generate-token` or `/game-list` still stop with an explicit error.

This is a test of proof transfer between the local browser and native HTTP stack;
the server may bind its proof to additional session state. Automated fixtures
validate the handoff, but successful native acceptance requires a live lobby test.

## Console diagnostics

Run `.\bin\krodin_client.exe` from PowerShell, then click Login. Authentication
messages use the `[auth]` stage in the existing console/network logger and also
appear in `logs/krunker-network.log` relative to the working directory. Watch the
file from a second terminal with:

```powershell
Get-Content .\logs\krunker-network.log -Wait -Tail 40
```

Each Join logs the executable path and `handoff=v2`, to identify stale binaries.
The handoff logs whether the browser token matches native cached access and which
optional socket parameters are present; their values are omitted.
Each browser request has an ID and elapsed milliseconds. Logs cover helper startup,
loader/runtime availability, profile selection, navigation, waiting for the username
flag, guest JWT detection, storage token acceptance, SDK renewal, encrypted cache saves/reuse, cancellation,
errors, and the pending Join continuation. Browser polling logs only state changes.
External navigation URLs, usernames, tokens, refresh credentials, raw browser
messages, and exception details never enter these authentication diagnostics.
An unknown helper code produces fixed text rather than printing its contents.

## Automated verification

Run from the repository root:

```powershell
build.bat check
build.bat tests none
odin test src/client -o:none -out:bin/client_tests.exe -define:ODIN_TEST_THREADS=1
node tools/browser_capture_test.mjs
node tools/captcha_handoff_test.mjs
```

The browser-access tests cover expiry boundaries, malformed claims, DPAPI round
trips/corruption, cache invalidation and forgetting, pipe framing and EOF. Client
tests cover browser-cache precedence, disabled Windows environment/`.env` loading,
the frozen invite, duplicate Join,
standalone Login without a connection, stale replies, cancellation, helper failures,
redacted status, and the single
authentication retry using fake browser and HTTP providers. The JavaScript tests
cover the username gate before token reads, the exact storage key, one-second settling,
guest platform claims despite a username/verified flag, expiry boundaries,
frame/origin rejection, storage errors, SDK renewal, and probe redaction. Node is needed only for
these JavaScript tests.

For a live SDK availability check without requesting a token:

```powershell
bin/krodin_browser.exe --probe
```

For live private-pipe and cancellation verification:

```powershell
odin build tools/browser_smoke -o:none -out:bin/browser_smoke.exe
bin/browser_smoke.exe
bin/browser_smoke.exe --captcha FRA:fixture
```

## Interactive verification

Use a real account and a user-provided lobby invite to finish these checks:

1. Forget the browser session, click Login with an empty invite, and complete login.
   Confirm it reports success without joining. Then paste a real invite and Join.
   Separately, verify Join can still request login and continue the same invite.
2. Restart and Join again. A usable cached token should avoid launching the helper.
3. Remove only `access-account.dpapi` with the client closed, retain the browser profile,
   and Join to check SDK renewal from the remembered login.
4. Cancel with the menu button and close the browser window on separate attempts;
   neither attempt should subsequently join.
5. On a Windows installation without Evergreen, verify the runtime-install message.
6. Join a live invite that returns `CaptchaRequired`. Complete verification in the
   helper. Confirm logs show capture armed, proof received, native matchmaking
   accepted, then native WebSocket connected. The helper should close. Cancel and
   close the window on separate attempts; neither should trigger a late Join.
   If the native retry still needs verification, it must stop after one handoff.

The live SDK probe has confirmed that the official page exposes the method in
WebView2. Login, remembered-account renewal, and a real lobby connection require
the user's interactive session and invite. Cross-target authentication-package
checks run without Windows dependencies; full Linux/macOS client builds require
the corresponding Odin STB/miniaudio vendor libraries on those platforms.
