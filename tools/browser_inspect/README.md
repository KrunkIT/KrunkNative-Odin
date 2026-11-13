# Embedded browser inspector

An independent Windows WebView2 host using the same minimal COM bindings as the
game's browser helper. It stays open until you close it. It never reads `.env`,
extracts tokens for the game, starts the game client, or stops after login.

Build and run from the repository root:

```powershell
build.bat inspect none
python -B tools/browser_inspect/inspect_browser.py "https://krunker.io/?game=NY:066nj"
```

The Python launcher uses only the standard library. It opens the separate
`bin/krodin_browser_inspect.exe`, attaches tracing while the page is still blank,
then navigates to the supplied URL. Its persistent profile is
`%LOCALAPPDATA%\Krodin\BrowserInspector`, independent of the game helper and regular
browsers. First use requires signing in again if you need an account session.
Use the official page normally, including any interactive Turnstile challenge.

The toolbar has an editable URL, Go, Reload, and DevTools. DevTools opens
automatically and provides the full live browser inspection tools:

- **Network:** enable **Preserve log**. Inspect the challenge requests,
  `/generate-token`, `/seek-game`, their initiators, headers, payloads, responses,
  cookies, and WebSocket messages. Raw values stay available here.
- **Sources:** pretty-print JavaScript, set breakpoints, and use fetch/XHR
  breakpoints on `seek-game` to inspect how its arguments were assembled.
- **Console:** evaluate JavaScript and inspect objects in the appropriate frame.
- **Application:** inspect localStorage, sessionStorage, cookies, and other storage.

There is no injected token extractor, fetch/XHR replacement, CAPTCHA solver, or
request replay. Network activity comes from the official page.

## Recorded trace

The launcher prints the trace path and a temporary loopback CDP port. It records
`logs/browser-inspector/<UTC timestamp>/events.jsonl`; `latest.txt` in that directory's
parent contains the newest trace path. This trace persists across navigation and
includes request IDs, frame/session IDs, timing, methods, redacted URLs, statuses,
header names, body field names/types/sizes, JavaScript initiator locations, storage
key changes, console argument types, and WebSocket frame directions/opcodes/sizes.
Separate iframe and worker targets are attached before their scripts resume, so
cross-origin challenge traffic is included when WebView2 exposes those targets.
Supported JSON/text API responses contribute field shapes and recognized error
codes, including `CaptchaRequired`.

Saved traces omit credential and unknown query/header values, request/response body
scalar contents, storage values, console values, and WebSocket payload contents.
They also omit opaque challenge URL paths. Use DevTools for full live values;
manual HAR exports from DevTools contain raw data and are separate from this trace.

Print only matchmaking/challenge records from the newest trace:

```powershell
python -B tools/browser_inspect/inspect_browser.py --summary (Get-Content logs/browser-inspector/latest.txt)
```

Closing the browser ends tracing. Ctrl+C ends tracing and closes only the inspector
launched by that process. `--seconds 30` provides a bounded recording. To attach
another recorder to an already running inspector, use `--attach <printed-port>`;
this neither navigates nor closes the existing browser on exit. The CDP endpoint
is local and exposes the live inspector session. It is enabled by the launcher,
not by the game client/helper. Starting the `.exe` directly opens DevTools without
enabling a CDP port; `--debug-port <port>` explicitly enables it.

## Verification

```powershell
python -B -m unittest discover -s tools/browser_inspect -p "test_*.py"
python -B tools/browser_inspect/smoke_inspector.py
```

The live smoke opens a local fixture page for eight seconds, covering HTTP POSTs,
an iframe request, localStorage changes, console messages, and WebSocket traffic.
It verifies that fixture credentials do not appear in the saved trace. It does
not contact Krunker or use real login credentials.
