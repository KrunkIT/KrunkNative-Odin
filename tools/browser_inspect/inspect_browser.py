#!/usr/bin/env python3
"""Launch the isolated Odin/WebView2 inspector and record a redacted CDP timeline.

Python standard library only. Full live contents remain available in DevTools.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
from pathlib import Path
import re
import secrets
import socket
import struct
import subprocess
import sys
import time
from datetime import datetime, timezone
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit
from urllib.request import ProxyHandler, build_opener

ROOT = Path(__file__).resolve().parents[2]
GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
INTERESTING = {"matchmaker.krunker.io", "gapi.svc.krunker.io", "challenges.cloudflare.com"}
BODY_HOSTS = {"matchmaker.krunker.io", "gapi.svc.krunker.io"}
ERROR_CODES = {"CaptchaRequired", "CAPTCHA_REQUIRED", "INVALID_TOKEN", "INVALID_ACCESS_TOKEN", "TOKEN_EXPIRED", "ACCESS_TOKEN_EXPIRED"}


def label(value: object) -> str:
    text = str(value)
    text = re.sub(r"eyJ[A-Za-z0-9_.=-]+", "[JWT omitted]", text)
    text = re.sub(r"[A-Za-z0-9_+=/-]{64,}", "[opaque value omitted]", text)
    return "".join(c if c >= " " and c != "\x7f" else " " for c in text)[:240]


def query_fields(query: str) -> list[dict]:
    result = []
    for key, value in parse_qsl(query, keep_blank_values=True, max_num_fields=1024):
        safe = key in {"hostname", "region", "game", "gameId", "autoChangeGame"} and re.fullmatch(r"[A-Za-z0-9_.:-]{0,80}", value)
        result.append({"name": label(key), "bytes": len(value.encode()), "value": value if safe else "[redacted]"})
    return result


def safe_url(value: str) -> str:
    try:
        parsed = urlsplit(value)
        if parsed.scheme not in {"http", "https", "ws", "wss"}:
            return parsed.scheme + ":[contents omitted]"
        host = parsed.hostname or ""
        if ":" in host:
            host = "[" + host + "]"
        if parsed.port:
            host += ":" + str(parsed.port)
        path = parsed.path
        marker = "/cdn-cgi/challenge-platform/"
        if marker in path:
            path = path.split(marker, 1)[0] + marker + "/".join(path.split(marker, 1)[1].split("/")[:3]) + "/[redacted]"
        else:
            path = "/".join("[redacted]" if len(part) > 48 else label(part) for part in path.split("/"))
        query = urlencode([(item["name"], item["value"]) for item in query_fields(parsed.query)])
        return urlunsplit((parsed.scheme, host, path, query, ""))
    except (ValueError, TypeError):
        return "[URL omitted]"


def shape(value: object, depth: int = 0) -> object:
    """Preserve field paths and types, never scalar contents from bodies/storage."""
    if depth >= 12:
        return {"type": "nested", "omitted": True}
    if isinstance(value, dict):
        return {label(key): shape(child, depth + 1) for key, child in list(value.items())[:128]}
    if isinstance(value, list):
        return {"type": "array", "length": len(value), "items": [shape(child, depth + 1) for child in value[:3]]}
    if isinstance(value, str):
        return {"type": "string", "bytes": len(value.encode())}
    return {"type": "null" if value is None else type(value).__name__}


def body_summary(body: str, content_type: str = "") -> dict:
    result = {"bytes": len(body.encode())}
    try:
        value = json.loads(body)
        result.update(encoding="json", shape=shape(value))
        if isinstance(value, dict):
            for key in ("error", "code", "message"):
                if isinstance(value.get(key), str) and value[key] in ERROR_CODES:
                    result["error_code"] = value[key]
    except (ValueError, RecursionError):
        # Padded base64 tokens also contain '='. Parse field names only when the
        # server/request explicitly identifies the body as form data.
        if content_type.partition(";")[0].strip().lower() == "application/x-www-form-urlencoded":
            try:
                result.update(encoding="form", fields=[{"name": label(k), "bytes": len(v.encode())} for k, v in parse_qsl(body, keep_blank_values=True, max_num_fields=256)])
            except ValueError:
                result["encoding"] = "opaque"
        else:
            result["encoding"] = "opaque"
    return result


def header_summary(headers: dict) -> dict:
    result = {}
    for key, raw in headers.items():
        name, value = str(key).lower(), str(raw)
        item = {"bytes": len(value.encode()), "value": "[redacted]"}
        if name in {"origin", "referer", "referrer"}:
            item["value"] = safe_url(value)
        elif name in {"content-type", "accept", "accept-encoding", "accept-language", "user-agent", "sec-fetch-site", "sec-fetch-mode", "sec-fetch-dest", "server", "cf-ray"}:
            item["value"] = label(value)
        elif name == "content-length" and value.isdecimal():
            item["value"] = value
        elif name == "cookie":
            item["names"] = [label(part.split("=", 1)[0].strip()) for part in value.split(";") if "=" in part]
        elif name == "set-cookie":
            item["names"] = [label(line.split("=", 1)[0].strip()) for line in value.splitlines() if "=" in line]
        result[label(key)] = item
    return result


def stack_summary(stack: dict) -> list[dict]:
    return [{"function": label(frame.get("functionName", "")), "url": safe_url(frame.get("url", "")),
             "line": frame.get("lineNumber"), "column": frame.get("columnNumber")}
            for frame in stack.get("callFrames", [])[:12]]


class CDP:
    """Small RFC 6455 client restricted to the local inspector debugging endpoint."""
    def __init__(self, url: str):
        parsed = urlsplit(url)
        if parsed.scheme != "ws" or parsed.hostname not in {"127.0.0.1", "localhost"}:
            raise ValueError("Only the local inspector CDP endpoint is accepted")
        self.sock = socket.create_connection((parsed.hostname, parsed.port), timeout=3)
        self.buffer = bytearray()
        self.next_id = 0
        self.on_message = lambda message: None
        key = base64.b64encode(secrets.token_bytes(16)).decode()
        target = parsed.path + ("?" + parsed.query if parsed.query else "")
        request = (f"GET {target} HTTP/1.1\r\nHost: {parsed.hostname}:{parsed.port}\r\n"
                   f"Upgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n")
        self.sock.sendall(request.encode("ascii"))
        while b"\r\n\r\n" not in self.buffer:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise EOFError("CDP handshake ended early")
            self.buffer.extend(chunk)
            if len(self.buffer) > 65536:
                raise RuntimeError("Invalid CDP WebSocket handshake")
        headers, rest = self.buffer.split(b"\r\n\r\n", 1)
        self.buffer = bytearray(rest)
        lines = headers.decode("iso-8859-1").split("\r\n")
        fields = {k.lower().strip(): v.strip() for line in lines[1:] for k, sep, v in [line.partition(":")] if sep}
        expected = base64.b64encode(hashlib.sha1((key + GUID).encode()).digest()).decode()
        if len(lines[0].split()) < 2 or lines[0].split()[1] != "101" or fields.get("sec-websocket-accept") != expected:
            raise RuntimeError("CDP WebSocket upgrade failed")
        self.fragment = bytearray()

    def send_frame(self, payload: bytes, opcode: int = 1) -> None:
        mask = secrets.token_bytes(4)
        length = len(payload)
        header = bytes([0x80 | opcode])
        header += bytes([0x80 | length]) if length < 126 else bytes([0xFE]) + struct.pack("!H", length) if length < 65536 else bytes([0xFF]) + struct.pack("!Q", length)
        self.sock.sendall(header + mask + bytes(value ^ mask[i % 4] for i, value in enumerate(payload)))

    def send(self, method: str, params: dict | None = None, session_id: str = "") -> int:
        self.next_id += 1
        message = {"id": self.next_id, "method": method, "params": params or {}}
        if session_id:
            message["sessionId"] = session_id
        self.send_frame(json.dumps(message).encode())
        return self.next_id

    def receive(self, timeout: float = 0.5) -> dict | None:
        self.sock.settimeout(timeout)
        while True:
            if len(self.buffer) >= 2:
                first, second = self.buffer[:2]
                length, pos = second & 127, 2
                size = 2 if length == 126 else 8 if length == 127 else 0
                if len(self.buffer) >= pos + size:
                    if size:
                        length = int.from_bytes(self.buffer[pos:pos + size], "big")
                        pos += size
                    if length > 16 * 1024 * 1024:
                        raise RuntimeError("CDP message exceeded 16 MiB")
                    mask_size = 4 if second & 128 else 0
                    if len(self.buffer) >= pos + mask_size + length:
                        mask = self.buffer[pos:pos + mask_size]
                        pos += mask_size
                        payload = bytes(self.buffer[pos:pos + length])
                        del self.buffer[:pos + length]
                        if mask:
                            payload = bytes(value ^ mask[i % 4] for i, value in enumerate(payload))
                        opcode = first & 15
                        if opcode == 8:
                            raise EOFError("Inspector debugging target closed")
                        if opcode == 9:
                            self.send_frame(payload, 10)
                        elif opcode in {0, 1}:
                            self.fragment.extend(payload)
                            if len(self.fragment) > 16 * 1024 * 1024:
                                raise RuntimeError("Fragmented CDP message exceeded 16 MiB")
                            if first & 128:
                                data, self.fragment = self.fragment, bytearray()
                                return json.loads(data)
                        continue
            try:
                chunk = self.sock.recv(65536)
            except socket.timeout:
                return None
            if not chunk:
                raise EOFError("Inspector disconnected")
            self.buffer.extend(chunk)

    def call(self, method: str, params: dict | None = None) -> dict:
        expected = self.send(method, params)
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            message = self.receive()
            if message is None:
                continue
            if message.get("id") == expected:
                if "error" in message:
                    raise RuntimeError(f"CDP {method} failed (code {message['error'].get('code')})")
                return message.get("result", {})
            self.on_message(message)
        raise TimeoutError("CDP command timed out: " + method)

    def close(self) -> None:
        self.sock.close()


class Recorder:
    def __init__(self, file, cdp: CDP):
        self.file, self.cdp = file, cdp
        self.started = time.monotonic()
        self.sequence = 0
        self.requests: dict[tuple[str, str], dict] = {}
        self.body_requests: dict[int, tuple[str, str]] = {}
        self.session_commands: dict[int, tuple[str, str]] = {}
        self.session_pending: dict[str, set[int]] = {}

    def write(self, record: dict) -> None:
        self.sequence += 1
        record = {"sequence": self.sequence, "elapsed_ms": round((time.monotonic() - self.started) * 1000, 2), **record}
        self.file.write(json.dumps(record, ensure_ascii=True) + "\n")
        self.file.flush()
        url = record.get("url", "")
        if any(host in url for host in INTERESTING) or record["event"].startswith("Inspector."):
            print(f"[{record['elapsed_ms'] / 1000:8.3f}s] {record['event']} {record.get('method', '')} {record.get('status', '')} {url}", flush=True)

    def consume(self, message: dict) -> None:
        command_id = message.get("id")
        if command_id in self.session_commands:
            session_id, method = self.session_commands.pop(command_id)
            pending = self.session_pending.get(session_id, set())
            pending.discard(command_id)
            if "error" in message:
                self.write({"event": "Inspector.protocolError", "session_id": session_id, "method": method, "code": message["error"].get("code")})
            if not pending:
                self.session_pending.pop(session_id, None)
                self.cdp.send("Runtime.runIfWaitingForDebugger", {}, session_id)
            return
        if message.get("id") in self.body_requests:
            session_id, request_id = self.body_requests.pop(message["id"])
            if "error" in message:
                self.write({"event": "Response.bodyUnavailable", "session_id": session_id, "request_id": request_id})
                return
            result = message.get("result", {})
            body = result.get("body", "")
            if result.get("base64Encoded"):
                try:
                    body = base64.b64decode(body).decode("utf-8")
                except (ValueError, UnicodeDecodeError):
                    body = ""
            mime = self.requests.get((session_id, request_id), {}).get("mime", "")
            self.write({"event": "Response.bodyShape", "session_id": session_id, "request_id": request_id, "body": body_summary(body, mime)})
            return
        event, data = message.get("method", ""), message.get("params", {})
        if event == "Target.attachedToTarget":
            session_id = data["sessionId"]
            target = data.get("targetInfo", {})
            self.write({"event": event, "session_id": session_id, "target_type": target.get("type"), "url": safe_url(target.get("url", ""))})
            pending = self.session_pending[session_id] = set()
            for method, params in [("Network.enable", {"maxPostDataSize": 131072}), ("Runtime.enable", {}),
                                   ("Target.setAutoAttach", {"autoAttach": True, "waitForDebuggerOnStart": True, "flatten": True})]:
                command_id = self.cdp.send(method, params, session_id)
                self.session_commands[command_id] = (session_id, method)
                pending.add(command_id)
            return
        if event == "Target.detachedFromTarget":
            session_id = data.get("sessionId", "")
            self.session_pending.pop(session_id, None)
            for command_id, (sid, _) in list(self.session_commands.items()):
                if sid == session_id:
                    self.session_commands.pop(command_id)
            self.write({"event": event, "session_id": session_id})
            return
        if not event.startswith(("Network.", "Page.frameNavigated", "DOMStorage.", "Runtime.consoleAPICalled", "Runtime.exceptionThrown")):
            return
        request_id = data.get("requestId", "")
        session_id = message.get("sessionId", "")
        request_key = (session_id, request_id)
        record = {"event": event, "session_id": session_id, "request_id": request_id, "timestamp": data.get("timestamp")}
        if event == "Network.requestWillBeSent":
            request = data.get("request", {})
            self.requests[request_key] = {"url": request.get("url", ""), "mime": ""}
            if len(self.requests) > 5000:
                self.requests.pop(next(iter(self.requests)))
            record.update(method=request.get("method"), url=safe_url(request.get("url", "")), resource_type=data.get("type"),
                          headers=header_summary(request.get("headers", {})), frame_id=data.get("frameId"),
                          initiator={"type": data.get("initiator", {}).get("type"), "stack": stack_summary(data.get("initiator", {}).get("stack", {}))})
            if "postData" in request:
                content_type = next((value for key, value in request.get("headers", {}).items() if key.lower() == "content-type"), "")
                record["body"] = body_summary(request["postData"], content_type)
            if "redirectResponse" in data:
                redirect = data["redirectResponse"]
                record["redirect"] = {"url": safe_url(redirect.get("url", "")), "status": redirect.get("status"), "headers": header_summary(redirect.get("headers", {}))}
        elif event in {"Network.responseReceived", "Network.webSocketHandshakeResponseReceived"}:
            response = data.get("response", {})
            record.update(url=safe_url(response.get("url", self.requests.get(request_key, {}).get("url", ""))), status=response.get("status"),
                          headers=header_summary(response.get("headers", {})), mime_type=label(response.get("mimeType", "")), protocol=label(response.get("protocol", "")))
            if request_key in self.requests:
                self.requests[request_key]["mime"] = response.get("mimeType", "")
        elif event in {"Network.requestWillBeSentExtraInfo", "Network.responseReceivedExtraInfo", "Network.webSocketWillSendHandshakeRequest"}:
            source = data.get("request", data)
            record.update(headers=header_summary(source.get("headers", {})), status=data.get("statusCode"))
        elif event in {"Network.webSocketFrameSent", "Network.webSocketFrameReceived"}:
            response = data.get("response", {})
            record.update(opcode=response.get("opcode"), payload_bytes=len(response.get("payloadData", "").encode()))
        elif event == "Network.webSocketCreated":
            self.requests[request_key] = {"url": data.get("url", ""), "mime": ""}
            record.update(url=safe_url(data.get("url", "")), initiator={"type": data.get("initiator", {}).get("type"), "stack": stack_summary(data.get("initiator", {}).get("stack", {}))})
        elif event == "Network.loadingFinished":
            record["encoded_bytes"] = data.get("encodedDataLength")
            info = self.requests.get(request_key, {})
            if urlsplit(info.get("url", "")).hostname in BODY_HOSTS and ("json" in info.get("mime", "") or info.get("mime", "").startswith("text/")):
                command_id = self.cdp.send("Network.getResponseBody", {"requestId": request_id}, session_id)
                self.body_requests[command_id] = request_key
        elif event == "Network.loadingFailed":
            record.update(canceled=data.get("canceled", False), error=label(data.get("errorText", "")))
        elif event == "Page.frameNavigated":
            frame = data.get("frame", {})
            record.update(frame_id=frame.get("id"), parent_id=frame.get("parentId"), url=safe_url(frame.get("url", "")))
        elif event.startswith("DOMStorage."):
            record.update(origin=safe_url(data.get("storageId", {}).get("securityOrigin", "")), key=label(data.get("key", "")),
                          old_bytes=len(data.get("oldValue", "").encode()), new_bytes=len(data.get("newValue", "").encode()))
        elif event == "Runtime.consoleAPICalled":
            record.update(console_type=data.get("type"), argument_types=[label(arg.get("type", "")) for arg in data.get("args", [])], stack=stack_summary(data.get("stackTrace", {})))
        elif event == "Runtime.exceptionThrown":
            details = data.get("exceptionDetails", {})
            record.update(exception_class=label(details.get("exception", {}).get("className", "")), stack=stack_summary(details.get("stackTrace", {})))
        else:
            return
        self.write(record)


def get_target(port: int, process=None) -> dict:
    opener = build_opener(ProxyHandler({}))
    deadline = time.monotonic() + 25
    while time.monotonic() < deadline:
        if process is not None and process.poll() is not None:
            raise RuntimeError(f"Inspector exited before its debugging endpoint became ready (exit {process.returncode})")
        try:
            with opener.open(f"http://127.0.0.1:{port}/json/list", timeout=1) as response:
                targets = json.load(response)
            for target in targets:
                if target.get("type") == "page" and not target.get("url", "").startswith("devtools:"):
                    return target
        except (OSError, ValueError):
            pass
        time.sleep(0.1)
    raise TimeoutError("Inspector debugging endpoint did not become ready")


def summarize(path: Path) -> None:
    with path.open(encoding="utf-8") as file:
        for line in file:
            record = json.loads(line)
            url = record.get("url", "")
            if any(host in url for host in INTERESTING) or record.get("body", {}).get("error_code"):
                print(json.dumps(record, ensure_ascii=True))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("url", nargs="?", default="https://krunker.io/")
    parser.add_argument("--attach", type=int, metavar="PORT", help="trace an existing inspector; leave its window open on exit")
    parser.add_argument("--seconds", type=float, default=0, help="bounded capture; default is until the browser closes or Ctrl+C")
    parser.add_argument("--summary", type=Path, help="print matchmaking/challenge records from an existing redacted trace")
    args = parser.parse_args()
    if args.summary:
        summarize(args.summary)
        return 0
    if args.seconds < 0 or (args.attach is not None and not 1 <= args.attach <= 65535):
        parser.error("Use a nonnegative duration and a port between 1 and 65535")
    if not (args.url.startswith("https://") or args.url.startswith("http://127.0.0.1:") or args.url == "about:blank"):
        parser.error("Use an HTTPS URL or the loopback smoke-test URL")
    process, cdp = None, None
    try:
        if args.attach:
            port = args.attach
        else:
            if sys.platform != "win32":
                raise RuntimeError("The embedded inspector host is Windows-only")
            binary = ROOT / "bin/krodin_browser_inspect.exe"
            if not binary.is_file():
                raise RuntimeError("Build the inspector first: build.bat inspect none")
            with socket.socket() as listener:
                listener.bind(("127.0.0.1", 0))
                port = listener.getsockname()[1]
            process = subprocess.Popen([str(binary), "--debug-port", str(port), "--wait-for-tracer", "--parent-pipe"],
                                       stdin=subprocess.PIPE, creationflags=subprocess.CREATE_NO_WINDOW)
        target = get_target(port, process)
        cdp = CDP(target["webSocketDebuggerUrl"])
        folder = ROOT / "logs/browser-inspector" / datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
        folder.mkdir(parents=True)
        trace_path = folder / "events.jsonl"
        (folder.parent / "latest.txt").write_text(str(trace_path), encoding="utf-8")
        print(f"Inspector CDP: 127.0.0.1:{port}\nRedacted trace: {trace_path}", flush=True)
        print("DevTools exposes live Network/Sources/Console/Application data. Enable Preserve log in Network.", flush=True)
        with trace_path.open("w", encoding="utf-8") as file:
            recorder = Recorder(file, cdp)
            cdp.on_message = recorder.consume
            recorder.write({"event": "Inspector.started", "url": safe_url(args.url), "debug_port": port})
            for method, params in [("Network.enable", {"maxTotalBufferSize": 16777216, "maxResourceBufferSize": 1048576, "maxPostDataSize": 131072}),
                                   ("Page.enable", {}), ("Runtime.enable", {}), ("DOMStorage.enable", {}),
                                   ("Target.setAutoAttach", {"autoAttach": True, "waitForDebuggerOnStart": True, "flatten": True})]:
                cdp.call(method, params)
            if not args.attach:
                cdp.call("Page.navigate", {"url": args.url})
            deadline = time.monotonic() + args.seconds if args.seconds else float("inf")
            try:
                while time.monotonic() < deadline and (process is None or process.poll() is None):
                    message = cdp.receive()
                    if message:
                        recorder.consume(message)
            except EOFError:
                pass
            except KeyboardInterrupt:
                print("Closing inspector capture.")
            recorder.write({"event": "Inspector.stopped"})
        return 0
    except (OSError, ValueError, RuntimeError, TimeoutError, EOFError) as error:
        print(f"Inspector error: {error}", file=sys.stderr)
        return 1
    finally:
        if cdp:
            cdp.close()
        if process and process.poll() is None:
            try:
                process.stdin.write(b"quit\n")
                process.stdin.flush()
                process.stdin.close()
                process.wait(timeout=5)
            except (OSError, subprocess.TimeoutExpired):
                process.terminate()


if __name__ == "__main__":
    raise SystemExit(main())
