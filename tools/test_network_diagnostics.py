"""Exercise native curl diagnostics against a local HTTP server; no account needed.

Build: odin build tools/network_diagnostics_test -out:bin/network_diagnostics_test.exe
Run:   python tools/test_network_diagnostics.py
"""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import base64
import hashlib
import json
import socket
import struct
import subprocess
import tempfile
import threading
from urllib.parse import parse_qs, urlsplit


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_args):
        pass

    def reply(self, status, body):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Request-ID", "fixture-request-403")
        self.send_header("Set-Cookie", "session=FAKE-COOKIE-SECRET; HttpOnly")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/ws":
            key = self.headers["Sec-WebSocket-Key"]
            accept = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
            self.send_response(101)
            self.send_header("Upgrade", "websocket")
            self.send_header("Connection", "Upgrade")
            self.send_header("Sec-WebSocket-Accept", accept)
            self.end_headers()
            # MessagePack [0, <52 KB string>] plus the two-byte trailer.
            payload = b"\x92\x00\xda" + struct.pack(">H", 52000) + b"x" * 52000 + b"\x00\x00"
            def frame(opcode, data):
                return bytes((opcode, 126)) + struct.pack(">H", len(data)) + data
            self.wfile.write(frame(0x02, payload[:30000]))  # nonfinal binary
            self.wfile.write(b"\x89\x04ping")  # control frame between fragments
            self.wfile.write(frame(0x80, payload[30000:]))  # final continuation
            self.wfile.flush()
            self.connection.settimeout(2)
            try:
                self.connection.recv(512)  # allow libcurl to answer the ping
            except (TimeoutError, ConnectionError):
                pass
            self.close_connection = True
        elif self.path.startswith("/seek-game?"):
            try:
                query = json.loads(parse_qs(urlsplit(self.path).query)["dataQuery"][0])
            except (json.JSONDecodeError, KeyError):
                self.reply(500, b'{"error":"SerdeError(expected value at line 1 column 1)"}')
            else:
                expected = {"v": "fixtureOpaqueVersion0123456789abcd"}
                self.reply(200 if query == expected else 400, b"seek verified" if query == expected else b"incorrect version")
        elif self.path.startswith("/reject?"):
            self.reply(403, b'{"error":"invite expired", "accessToken":"FAKE-BODY-SECRET", "clientId":"FAKE-CLIENT-SECRET", "detail":"registered-secret-echo"}')
        elif self.path == "/success":
            self.reply(200, b"SECRET-SUCCESS-BODY")
        elif self.path == "/drop":
            self.close_connection = True
            self.connection.shutdown(socket.SHUT_RDWR)
            self.connection.close()
        else:
            self.reply(404, b'{"error":"missing fixture"}')

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        expected = b'{"test":"POST body remains alive through perform"}'
        self.reply(200 if body == expected else 400, b"POST verified" if body == expected else b"POST corrupt")


def main():
    root = Path(__file__).resolve().parents[1]
    executable = root / "bin/network_diagnostics_test.exe"
    with ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        try:
            with tempfile.TemporaryDirectory(prefix="krunker-network-test-") as workdir:
                run = subprocess.run([str(executable), f"http://127.0.0.1:{server.server_port}"], cwd=workdir, capture_output=True, text=True, timeout=30)
                log = (Path(workdir) / "logs/krunker-network.log").read_text()
                combined = run.stdout + run.stderr + log
                for secret in ("FAKE-QUERY-SECRET", "FAKE-BODY-SECRET", "FAKE-CLIENT-SECRET", "FAKE-COOKIE-SECRET", "registered-secret-echo", "SECRET-SUCCESS-BODY"):
                    assert secret not in combined, "A fixture credential escaped redaction"
                assert run.returncode == 0, combined
                for expected in ("Real libcurl chunked/fragmented WebSocket", "HTTP=500", "SerdeError", "mock-seek-valid", "HTTP=200", "HTTP=403", "invite expired", "fixture-request-403", "timings_ms", "mock-drop", "Empty reply from server", "Offline network diagnostic integration tests OK"):
                    assert expected in combined, f"Missing diagnostic evidence: {expected}"
                assert "invite expired" in log and "HTTP=403" in log, "Failure not persisted to log"
                print("Native WebSocket fragmentation/ping and HTTP diagnostics integration tests OK")
        finally:
            server.shutdown()
            worker.join(timeout=5)


if __name__ == "__main__":
    main()
