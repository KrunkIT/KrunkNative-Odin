"""Bounded live WebView2 check using only a local fixture page and fake credentials."""
import base64
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import subprocess
import sys
import threading

ROOT = Path(__file__).resolve().parents[2]


class Fixture(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        if self.path.startswith("/ws"):
            key = self.headers["Sec-WebSocket-Key"]
            accept = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
            self.send_response(101)
            self.send_header("Upgrade", "websocket")
            self.send_header("Connection", "Upgrade")
            self.send_header("Sec-WebSocket-Accept", accept)
            self.end_headers()
            payload = b"fixture-ws-secret"
            self.wfile.write(bytes([0x81, len(payload)]) + payload)
            self.wfile.flush()
            return
        if self.path.startswith("/frame"):
            body = b'<script>fetch("/frame-post", {method:"POST",body:"proof=fixture-frame-secret"}); console.log("fixture-frame-console-secret");</script>'
        else:
            body = ('''<!doctype html><title>Inspector smoke fixture</title>
<h1>Local inspector smoke test</h1>
<iframe src="http://localhost:PORT/frame"></iframe>
<script>
localStorage.setItem('inspector_fixture', 'fixture-storage-secret');
console.log('fixture-console-secret');
fetch('/probe?accessToken=fixture-query-secret&captchaToken=fixture-captcha-secret', {
    method:'POST', headers:{'Content-Type':'application/json','X-Inspector-Proof':'fixture-header-secret'},
    body:JSON.stringify({username:'fixture-user-secret',password:'fixture-password-secret',nested:{proof:'fixture-proof-secret'}})
}).then(() => { let ws = new WebSocket('ws://127.0.0.1:PORT/ws?clientKey=fixture-key-secret'); ws.onmessage=() => { document.title='Inspector smoke complete'; }; });
</script>'''.replace("PORT", str(self.server.server_port))).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", "0")))
        body = b'{"error":"CaptchaRequired","access_token":"fixture-response-secret"}'
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main():
    with ThreadingHTTPServer(("127.0.0.1", 0), Fixture) as server:
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            result = subprocess.run([sys.executable, "-B", str(Path(__file__).with_name("inspect_browser.py")),
                                     f"http://127.0.0.1:{server.server_port}/", "--seconds", "8"],
                                    cwd=ROOT, capture_output=True, text=True, timeout=60)
        finally:
            server.shutdown()
    print(result.stdout)
    if result.returncode:
        print(result.stderr, file=sys.stderr)
        return 1
    path = Path((ROOT / "logs/browser-inspector/latest.txt").read_text(encoding="utf-8"))
    text = path.read_text(encoding="utf-8")
    records = [json.loads(line) for line in text.splitlines()]
    events = {record["event"] for record in records}
    required = {"Network.requestWillBeSent", "Network.responseReceived", "Network.webSocketCreated", "Network.webSocketFrameReceived",
                "DOMStorage.domStorageItemAdded", "Runtime.consoleAPICalled", "Inspector.stopped"}
    assert required <= events, "Missing live events: " + repr(required - events)
    assert any("/frame-post" in record.get("url", "") for record in records), "Iframe network request was not recorded"
    for secret in ("fixture-storage-secret", "fixture-console-secret", "fixture-query-secret", "fixture-captcha-secret", "fixture-header-secret",
                   "fixture-user-secret", "fixture-password-secret", "fixture-proof-secret", "fixture-key-secret", "fixture-ws-secret",
                   "fixture-response-secret", "fixture-frame-secret", "fixture-frame-console-secret"):
        assert secret not in text, "A fixture secret escaped redaction"
    print(f"Live inspector smoke passed: {len(records)} events, including iframe traffic; fixture secrets omitted.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
