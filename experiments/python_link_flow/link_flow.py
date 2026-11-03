#!/usr/bin/env python3
"""Small, dependency-free Krunker invite and MessagePack flow experiment."""

from __future__ import annotations

import base64
import hashlib
import json
import os
import secrets
import socket
import struct
import ssl
import sys
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, urlencode, urlsplit
from urllib.request import Request, urlopen

try:
    import websocket_client as _websocket  # type: ignore[import-not-found]
except ImportError:
    try:
        import websocket as _websocket  # type: ignore[import-not-found]
    except ImportError:
        _websocket = None

from krunker_msgpack import AhNum, HosterAhNum, decode_packets


MATCHMAKER = "https://matchmaker.krunker.io"
ORIGIN = "https://krunker.io"
USER_AGENT = "Mozilla/5.0 (Krodin Python link-flow experiment)"
WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


class FlowError(RuntimeError):
    def __init__(self, stage: str, message: str, exit_code: int = 5):
        super().__init__(message)
        self.stage = stage
        self.exit_code = exit_code


def fail(stage: str, message: str, exit_code: int = 5) -> FlowError:
    return FlowError(stage, message, exit_code)


def env_flag(name: str, default: bool = False) -> bool:
    """Read a boolean experiment switch without treating ``0`` as enabled."""
    value = os.environ.get(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def load_dotenv() -> None:
    """Load KRUNKER_ACCESS_TOKEN without requiring python-dotenv."""
    candidates = [
        Path.cwd() / ".env",
        Path(__file__).resolve().parent / ".env",
        Path(__file__).resolve().parents[2] / ".env",
    ]
    for path in candidates:
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except OSError:
            continue
        for line in lines:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("export "):
                line = line[7:].strip()
            key, separator, value = line.partition("=")
            if separator and key.strip() == "KRUNKER_ACCESS_TOKEN":
                value = value.strip()
                if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                    value = value[1:-1]
                if value and not os.environ.get("KRUNKER_ACCESS_TOKEN"):
                    os.environ["KRUNKER_ACCESS_TOKEN"] = value
                return


def parse_link(raw: str) -> dict[str, str | int]:
    raw = raw.strip()
    if not raw:
        raise fail("parse", "the link is empty", 3)
    if "://" not in raw:
        if any(c in raw for c in "=/"):
            raw = "https://" + raw
        else:
            return {"raw": raw, "scheme": "game", "host": "", "port": 0, "path": "", "game_id": raw}

    parsed = urlsplit(raw)
    if parsed.scheme.lower() not in {"http", "https", "ws", "wss", "tcp", "krunker"}:
        raise fail("parse", f"unsupported scheme: {parsed.scheme}", 3)
    if not parsed.hostname and parsed.scheme.lower() != "game":
        raise fail("parse", "the link has no host", 3)
    query = parse_qs(parsed.query, keep_blank_values=True)
    game_id = (query.get("game") or query.get("gameId") or [""])[0]
    return {
        "raw": raw,
        "scheme": parsed.scheme.lower(),
        "host": parsed.hostname or "",
        "port": parsed.port or 0,
        "path": parsed.path,
        "game_id": game_id,
        "client_key": (query.get("clientKey") or [""])[0],
        "access_token": (query.get("at") or [""])[0],
    }


def http_get(url: str) -> tuple[int, bytes]:
    request = Request(url, headers={"Origin": ORIGIN, "Referer": ORIGIN + "/", "User-Agent": USER_AGENT})
    try:
        with urlopen(request, timeout=15) as response:
            return response.status, response.read()
    except HTTPError as error:
        body = error.read()
        return error.code, body
    except (URLError, TimeoutError, OSError) as error:
        raise fail("transport", f"HTTP request failed: {error}") from error


def assigned_wss_probe(url: str) -> None:
    parsed = urlsplit(url)
    if parsed.scheme != "wss" or not parsed.hostname:
        raise fail("websocket", "assigned endpoint is not a valid wss URL")
    port = parsed.port or 443
    target = parsed.path or "/"
    if parsed.query:
        target += "?" + parsed.query
    key = base64.b64encode(secrets.token_bytes(16)).decode("ascii")
    request = (
        f"GET {target} HTTP/1.1\r\n"
        f"Host: {parsed.hostname}:{port}\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        f"Origin: {ORIGIN}\r\n"
        f"Referer: {ORIGIN}/\r\n"
        f"User-Agent: {USER_AGENT}\r\n\r\n"
    ).encode("ascii")
    try:
        with socket.create_connection((parsed.hostname, port), timeout=15) as tcp:
            context = ssl.create_default_context()
            with context.wrap_socket(tcp, server_hostname=parsed.hostname) as tls:
                tls.sendall(request)
                response = b""
                while b"\r\n\r\n" not in response and len(response) < 65536:
                    chunk = tls.recv(4096)
                    if not chunk:
                        break
                    response += chunk
    except (OSError, ssl.SSLError, TimeoutError) as error:
        raise fail("websocket", f"TLS/WebSocket connection failed: {error}") from error

    header_blob = response.split(b"\r\n\r\n", 1)[0]
    lines = header_blob.decode("iso-8859-1", errors="replace").split("\r\n")
    if not lines:
        raise fail("websocket", "server returned no HTTP upgrade response")
    status_line = lines[0]
    try:
        status = int(status_line.split()[1])
    except (IndexError, ValueError) as error:
        raise fail("websocket", f"invalid upgrade status line: {status_line}") from error
    headers = {}
    for line in lines[1:]:
        name, separator, value = line.partition(":")
        if separator:
            headers[name.lower().strip()] = value.strip()
    expected = base64.b64encode(hashlib.sha1((key + WS_GUID).encode("ascii")).digest()).decode("ascii")
    if status != 101:
        raise fail("websocket", f"upgrade rejected with HTTP {status}")
    if headers.get("sec-websocket-accept") != expected:
        raise fail("websocket", "upgrade response had an invalid Sec-WebSocket-Accept")


def player_enter_message() -> list[object]:
    primary = int(os.environ.get("KRUNKER_PRIMARY", "2482"))
    return [
        "en",
        [
            0, primary, [-1, -1], -1, -1, 2, 0, 0, 1, -1, -1, 1, 0, -1, -1,
            -1, -1, -1, -1, 0, -1, -1, 1, 1, 1, -1, -1, -1, 0, [None, -1],
            -1, -1, -1, 1,
        ],
        16, 18, False, False, False, False, False, False, None, False, False, False,
    ]


def initial_player_messages() -> list[list[object]]:
    spectator = bool(os.environ.get("KRUNKER_SPECTATOR"))
    welcome_name = os.environ.get("KRUNKER_SPEECH_NAME", "Guest")
    messages = [
        ["sb", "welc", welcome_name],
        ["po"],
        player_enter_message(),
        ["q", 0, 0, [8, 33], 0, [0, -4712], {
            "0-4": -1, "0-5": 0, "0-6": 0, "0-7": 0, "0-8": 0,
            "0-9": 0, "0-10": 0, "0-11": 0, "0-12": 0, "0-13": 0, "0-14": 0,
        }],
        ["q", 0, 2, [8, 12, 15], 0],
        ["q", 0, 5, [22, 11, 8], 0],
        ["q", 0, 8, [10, 12, 5, 6, 6], 0],
        ["q", 0, 8, [10, 12, 5, 6, 6], 0],
        ["v"],
    ]
    if spectator:
        enter = next(message for message in messages if message[0] == "en")
        messages = [enter, ["cd", "t", 7], ["v"]]
        if os.environ.get("KRUNKER_SPECTATOR_ONLY"):
            messages = [enter]
    # ``sb`` is an account/session announcement, not part of the minimum
    # player-entry handshake.  Omit it unless explicitly requested; an
    # invented name or null value can be rejected by some deployments.
    if not env_flag("KRUNKER_SEND_SB") and not spectator:
        messages.pop(0)
    if os.environ.get("KRUNKER_SKIP_PO"):
        messages = [message for message in messages if message[0] != "po"]
    # Competitive/custom lobbies commonly require an explicit team before an
    # entry request can spawn. Team 1 is the browser-compatible default; set
    # KRUNKER_TEAM=2 to exercise the other side.
    team = os.environ.get("KRUNKER_TEAM", "1")
    if team and not spectator:
        try:
            team_value = int(team)
        except ValueError as error:
            raise ValueError("KRUNKER_TEAM must be 1 or 2") from error
        try:
            class_value = int(os.environ.get("KRUNKER_CLASS", "2"))
        except ValueError as error:
            raise ValueError("KRUNKER_CLASS must be a numeric class index") from error
        enter_index = next(index for index, message in enumerate(messages) if message[0] == "en")
        messages[enter_index + 1:enter_index + 1] = [
            ["cd", "t", team_value],
            ["cd", "c", {"c": class_value, "s": None}],
            player_enter_message(),
        ]
    if os.environ.get("KRUNKER_SPECTATOR"):
        enter = messages.index(next(message for message in messages if message[0] == "en"))
        messages[enter][1][6] = 1
    return messages


def messagepack_probe(url: str, spawn: bool = False, step: bool = False, stay: bool = False) -> None:
    # The standard-library path owns the stateful bootstrap. In particular it
    # can wait for the server's initial load packet and handle control frames
    # between application packets. Keeping one transport implementation avoids
    # the optional client's easy-to-miss early-send race.
    if _websocket is None:
        print("[link-flow] websocket-client unavailable; using the standard-library probe")
    else:
        print("[link-flow] using the standard-library probe for deterministic packet ordering")
    try:
        _raw_messagepack_probe(url, spawn, step, stay)
    except KeyboardInterrupt:
        print("[link-flow] Ctrl+C received; closing the connection")
    except Exception as error:
        raise fail("protocol", f"MessagePack probe failed: {error}") from error


def _raw_read_exact(stream: ssl.SSLSocket, count: int, buffered: bytes = b"") -> tuple[bytes, bytes]:
    data = buffered
    while len(data) < count:
        chunk = stream.recv(count - len(data))
        if not chunk:
            raise OSError("WebSocket closed while reading a frame")
        data += chunk
    return data[:count], data[count:]


def _raw_send_frame(stream: ssl.SSLSocket, payload: bytes, opcode: int = 2) -> None:
    mask = secrets.token_bytes(4)
    length = len(payload)
    if length < 126:
        header = bytes((0x80 | opcode, 0x80 | length))
    elif length < 65536:
        header = bytes((0x80 | opcode, 0x80 | 126)) + struct.pack(">H", length)
    else:
        header = bytes((0x80 | opcode, 0x80 | 127)) + struct.pack(">Q", length)
    masked = bytes(value ^ mask[index % 4] for index, value in enumerate(payload))
    stream.sendall(header + mask + masked)


def _raw_recv_frame(stream: ssl.SSLSocket, buffered: bytes = b"") -> tuple[int, bytes, bytes]:
    header, buffered = _raw_read_exact(stream, 2, buffered)
    first, second = header
    opcode = first & 0x0F
    masked = bool(second & 0x80)
    length = second & 0x7F
    if length == 126:
        extended, buffered = _raw_read_exact(stream, 2, buffered)
        length = struct.unpack(">H", extended)[0]
    elif length == 127:
        extended, buffered = _raw_read_exact(stream, 8, buffered)
        length = struct.unpack(">Q", extended)[0]
    if masked:
        mask, buffered = _raw_read_exact(stream, 4, buffered)
    else:
        mask = b""
    payload, buffered = _raw_read_exact(stream, length, buffered)
    if mask:
        payload = bytes(value ^ mask[index % 4] for index, value in enumerate(payload))
    return opcode, payload, buffered


def _raw_open_ws(url: str) -> tuple[ssl.SSLSocket, bytes]:
    parsed = urlsplit(url)
    if parsed.scheme != "wss" or not parsed.hostname:
        raise OSError("assigned endpoint is not a valid wss URL")
    port = parsed.port or 443
    target = parsed.path or "/"
    if parsed.query:
        target += "?" + parsed.query
    key = base64.b64encode(secrets.token_bytes(16)).decode("ascii")
    request = (
        f"GET {target} HTTP/1.1\r\n"
        f"Host: {parsed.hostname}:{port}\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        f"Origin: {ORIGIN}\r\n"
        f"Referer: {ORIGIN}/\r\n"
        f"User-Agent: {USER_AGENT}\r\n\r\n"
    ).encode("ascii")
    tcp = socket.create_connection((parsed.hostname, port), timeout=15)
    stream = ssl.create_default_context().wrap_socket(tcp, server_hostname=parsed.hostname)
    stream.sendall(request)
    response = b""
    while b"\r\n\r\n" not in response and len(response) < 65536:
        response += stream.recv(4096)
    header_blob = response.split(b"\r\n\r\n", 1)[0]
    lines = header_blob.decode("iso-8859-1", errors="replace").split("\r\n")
    if not lines or len(lines[0].split()) < 2 or int(lines[0].split()[1]) != 101:
        stream.close()
        raise OSError("WebSocket upgrade was not HTTP 101")
    headers = {}
    for line in lines[1:]:
        name, separator, value = line.partition(":")
        if separator:
            headers[name.lower().strip()] = value.strip()
    expected = base64.b64encode(hashlib.sha1((key + WS_GUID).encode("ascii")).digest()).decode("ascii")
    if headers.get("sec-websocket-accept") != expected:
        stream.close()
        raise OSError("invalid Sec-WebSocket-Accept")
    return stream, response.split(b"\r\n\r\n", 1)[1]


def _raw_log_binary(
    payload: bytes, *, quiet_wait: bool = False, quiet_routine: bool = False
) -> tuple[bool, bool, bool]:
    try:
        ah_num, messages = decode_packets(payload)
    except ValueError as error:
        print(f"[link-flow][ERROR][msgpack] malformed binary packet: {error}")
        return False, False, False
    opcodes = [message[0] for message in messages if isinstance(message, list) and message]
    is_wait = any(
        isinstance(message, list)
        and len(message) > 1
        and message[0] == "gmsg"
        and message[1] == "wt"
        for message in messages
    )
    details: list[str] = []
    for message in messages:
        if not isinstance(message, list) or not message or not isinstance(message[0], str):
            continue
        opcode = message[0]
        if opcode == "init" and len(message) > 7 and isinstance(message[7], dict):
            config = message[7]
            details.append(
                "init(minPlayers={0}, maxPlayers={1}, forceSpawn={2})".format(
                    config.get("minPlayers", "?"), config.get("maxPlayers", "?"), config.get("forceSpawn", "?")
                )
            )
        elif opcode == "cd" and len(message) > 1 and isinstance(message[1], dict):
            records = list(message[1].values())
            active = sum(1 for record in records if isinstance(record, dict) and record.get("a"))
            selected = sum(1 for record in records if isinstance(record, dict) and record.get("c") is not None)
            details.append(f"lobby-players={len(records)} active={active} classes={selected}")
        elif opcode == "fe" and len(message) > 1:
            details.append(f"error={message[1]!r}")
        elif opcode == "cda":
            assignment = message[2] if len(message) > 2 and isinstance(message[2], dict) else {}
            details.append(f"team={assignment.get('t', '?')} player={message[1] if len(message) > 1 else '?'}")
        elif opcode == "gmsg" and len(message) > 1:
            details.append(f"message={message[1]!r}")
        elif opcode == "start":
            # The first fields are timer/team/spectator/movement state. Keep
            # the probe readable while retaining enough to diagnose spawn.
            details.append(f"start-fields={message[1:5]!r}")
        elif opcode == "ready" and len(message) > 1:
            details.append(f"ready={message[1]!r}")
    suffix = f" details={' ; '.join(details)}" if details else ""
    interesting = any(
        opcode in {"start", "gmsg", "gsc", "fe", "cda", "end", "lrmr", "ub", "dc"}
        for opcode in opcodes
    )
    if not ((quiet_wait and is_wait) or (quiet_routine and not interesting)):
        print(
            f"[link-flow] received binary: trailer={payload[-2:].hex(' ')} "
            f"ahNum={ah_num} opcodes={opcodes} bytes={len(payload)}{suffix}"
        )
    return "load" in opcodes, "start" in opcodes, is_wait


def _raw_wait_application(stream: ssl.SSLSocket, buffered: bytes, timeout: float = 2.0) -> tuple[bytes, bool]:
    """Read one binary application packet, handling control frames."""
    stream.settimeout(timeout)
    while True:
        try:
            opcode, payload, buffered = _raw_recv_frame(stream, buffered)
        except (socket.timeout, TimeoutError):
            print("[link-flow][WARN][bootstrap] no response before step timeout")
            return buffered, False
        if opcode == 0x8:
            print("[link-flow][ERROR][protocol] server closed WebSocket during bootstrap")
            return buffered, True
        if opcode == 0x9:
            _raw_send_frame(stream, payload, opcode=0xA)
            continue
        if opcode != 0x2:
            print(f"[link-flow][WARN][protocol] ignored WebSocket opcode={opcode} bytes={len(payload)}")
            continue
        _raw_log_binary(payload)
        return buffered, False


def _raw_messagepack_probe(
    url: str, spawn: bool = False, step: bool = False, stay: bool = False
) -> None:
    stream, buffered = _raw_open_ws(url)
    try:
        counter = HosterAhNum() if os.environ.get("KRUNKER_COUNTER") == "hoster" else AhNum()
        # The game server announces its session with ["load", ...] before it
        # accepts the client's acknowledgement. This ordering is required for
        # every MessagePack probe. Set KRUNKER_EARLY_LOAD=1 only when testing
        # the old/early-send failure mode.
        load_after_server = not env_flag("KRUNKER_EARLY_LOAD")
        if load_after_server:
            stream.settimeout(8)
            saw_load = False
            for _ in range(8):
                opcode, payload, buffered = _raw_recv_frame(stream, buffered)
                if opcode == 0x9:
                    _raw_send_frame(stream, payload, opcode=0xA)
                elif opcode == 0x2:
                    saw_load = _raw_log_binary(payload)[0] or saw_load
                if saw_load:
                    break
            if not saw_load:
                print("[link-flow][ERROR][bootstrap] server never sent load before acknowledgement")
                return
        frame = counter.encode(["load"])
        print(f"[link-flow] sending load: {frame.hex(' ')}")
        _raw_send_frame(stream, frame)
        if spawn:
            # Wait until the server has accepted load before sending the
            # stateful player bootstrap. Sending it too early yields 000008.
            stream.settimeout(8)
            for _ in range(8):
                try:
                    opcode, payload, buffered = _raw_recv_frame(stream, buffered)
                except (socket.timeout, TimeoutError):
                    break
                if opcode == 0x8:
                    print("[link-flow] server closed before player bootstrap")
                    return
                if opcode == 0x9:
                    _raw_send_frame(stream, payload, opcode=0xA)
                    continue
                if opcode == 0x2 and _raw_log_binary(payload)[0]:
                    break
            for index, message in enumerate(initial_player_messages(), 1):
                frame = counter.encode(message)
                print(f"[link-flow] sending {message[0]}: {len(frame)} bytes")
                _raw_send_frame(stream, frame)
                if step:
                    buffered, closed = _raw_wait_application(stream, buffered, 3.0)
                    if closed:
                        print(f"[link-flow][ERROR][bootstrap] server rejected step {index} ({message[0]})")
                        return
                else:
                    time.sleep(0.5)
        stream.settimeout(5)
        deadline = (
            time.monotonic() + float(os.environ.get("KRUNKER_SPAWN_TIMEOUT", "90"))
            if spawn and not stay
            else None
        )
        waiting_logged = False
        started = False
        iterations = 0
        while stay or iterations < (16 if not spawn else 4096):
            iterations += 1
            if deadline is not None and time.monotonic() >= deadline:
                if waiting_logged:
                    print(
                        "[link-flow][WARN][spawn] timed out while server reports waiting "
                        "(gmsg wt); reach the lobby minimum before expecting start"
                    )
                else:
                    print("[link-flow][WARN][spawn] timed out waiting for start")
                break
            try:
                opcode, payload, buffered = _raw_recv_frame(stream, buffered)
            except (socket.timeout, TimeoutError):
                if stay or (deadline is not None and time.monotonic() < deadline):
                    continue
                print("[link-flow][WARN][protocol] no more frames before timeout")
                break
            if opcode == 0x8:
                print("[link-flow] server sent WebSocket close")
                break
            if opcode == 0x9:
                _raw_send_frame(stream, payload, opcode=0xA)
                continue
            if opcode != 0x2:
                print(f"[link-flow] received WebSocket opcode={opcode} bytes={len(payload)}")
                continue
            _, saw_start, is_wait = _raw_log_binary(
                payload, quiet_wait=waiting_logged, quiet_routine=started
            )
            waiting_logged = waiting_logged or is_wait
            if saw_start:
                print("[link-flow][OK][spawn] server sent start; player entered the match")
                started = True
                if stay:
                    print("[link-flow][OK][stay] connected; press Ctrl+C to leave")
                else:
                    break
    finally:
        stream.close()


def run_browser_invite(
    link: dict[str, str | int],
    packet_probe: bool = False,
    spawn: bool = False,
    step: bool = False,
    stay: bool = False,
) -> None:
    game_id = str(link["game_id"])
    if not game_id:
        raise fail("invite", "browser invite has no game query parameter", 4)
    token = os.environ.get("KRUNKER_ACCESS_TOKEN", "")
    if not token:
        raise fail("access-token", "set KRUNKER_ACCESS_TOKEN in .env or the environment")

    print("[1/6] Fetching validation token...")
    status, body = http_get(MATCHMAKER + "/generate-token")
    if not 200 <= status < 300 or not body.strip():
        raise fail("validation-token", f"HTTP {status} or empty response")
    validation = body.decode("utf-8").strip()
    print(f"[link-flow] validation token: {len(validation)} bytes")

    print("[2/6] Fetching game version...")
    status, body = http_get(MATCHMAKER + "/game-list?hostname=krunker.io")
    version = "1.0.0"
    if 200 <= status < 300:
        try:
            games = json.loads(body.decode("utf-8"))
            if isinstance(games, dict):
                games = games.get("games", [])
            for game in games if isinstance(games, list) else []:
                if isinstance(game, list) and len(game) > 4 and isinstance(game[4], dict) and game[4].get("v"):
                    version = str(game[4]["v"])
                    break
        except (UnicodeDecodeError, json.JSONDecodeError, TypeError):
            print("[link-flow][WARN][game-list] invalid JSON; using version 1.0.0")
    else:
        print(f"[link-flow][WARN][game-list] HTTP {status}; using version 1.0.0")
    print(f"[link-flow] game version: {version}")

    print("[3/6] Resolving invite through /seek-game...")
    query = {
        "hostname": "krunker.io",
        "region": "sgp",
        "autoChangeGame": "false",
        "validationToken": validation,
        "dataQuery": json.dumps({"v": version}, separators=(",", ":")),
        "accessToken": token,
        "game": game_id,
    }
    status, body = http_get(MATCHMAKER + "/seek-game?" + urlencode(query))
    print(f"[link-flow] seek-game HTTP status: {status}")
    if not 200 <= status < 300:
        raise fail("seek-game", body.decode("utf-8", errors="replace"))
    try:
        assignment = json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise fail("assignment", f"invalid JSON response: {error}") from error
    if not isinstance(assignment, dict):
        raise fail("assignment", "response was not a JSON object")
    host = assignment.get("host")
    client_key = assignment.get("clientId")
    assigned_game = assignment.get("gameId")
    if not all(isinstance(value, str) and value for value in (host, client_key, assigned_game)):
        raise fail("assignment", "response is missing host, clientId, or gameId")
    print(f"[link-flow] assignment: host={host} gameId={assigned_game} clientId={client_key}")

    print("[4/6] Building assigned WSS URL...")
    ws_url = "wss://" + str(host) + "/ws?" + urlencode({"gameId": assigned_game, "clientKey": client_key, "at": token})
    print(f"[link-flow] websocket URL: wss://{host}/ws?gameId={assigned_game}&clientKey={client_key}&at=<redacted>")
    if packet_probe:
        print("[5/6] Performing upgrade and sending MessagePack probe...")
        messagepack_probe(ws_url, spawn, step, stay)
    else:
        print("[5/6] Performing TLS/WebSocket upgrade...")
        assigned_wss_probe(ws_url)
        print("[link-flow] websocket upgrade: OK")
        print("[6/6] Protocol handshake check...")
        print("[link-flow][WARN][protocol] use --packets to send/load and decode MessagePack frames")


def main() -> int:
    if len(sys.argv) not in (2, 3, 4) or (len(sys.argv) >= 3 and sys.argv[2] not in {"--packets", "--spawn", "--stay"}) or (len(sys.argv) == 4 and sys.argv[3] != "--step"):
        print("Usage: python link_flow.py <lobby-link> [--packets|--spawn|--stay [--step]]")
        return 2
    load_dotenv()
    packet_probe = len(sys.argv) >= 3
    stay = packet_probe and sys.argv[2] == "--stay"
    spawn = packet_probe and sys.argv[2] in {"--spawn", "--stay"}
    step = len(sys.argv) == 4 and sys.argv[3] == "--step"
    if stay:
        # The persistent variant is deliberately opinionated for this test:
        # team 2 and Run N Gun (the SMG class, index 2). Environment values
        # still provide an escape hatch when the lobby has class limits.
        os.environ.setdefault("KRUNKER_TEAM", "2")
        os.environ.setdefault("KRUNKER_CLASS", "2")
    try:
        link = parse_link(sys.argv[1])
        print(f"[link-flow] input: {link['raw']}")
        print(f"[link-flow] parse: OK ({link['scheme']}://{link['host'] or '<invite>'})")
        scheme = str(link["scheme"])
        if scheme in {"http", "https", "game"}:
            run_browser_invite(link, packet_probe, spawn, step, stay)
        elif scheme in {"ws", "wss"}:
            if not link["host"] or not link["game_id"] or not link.get("client_key") or not link.get("access_token"):
                raise fail("endpoint", "direct WSS links require host, gameId, clientKey, and at")
            print("[1/2] Performing direct TLS/WebSocket upgrade...")
            assigned_wss_probe(str(link["raw"]))
            print("[link-flow] websocket upgrade: OK")
            if packet_probe:
                messagepack_probe(str(link["raw"]), spawn, step, stay)
            else:
                print("[link-flow][WARN][protocol] use --packets to send/load and decode MessagePack frames")
        elif scheme in {"tcp", "krunker"}:
            host = str(link["host"])
            port = int(link["port"] or 21015)
            print(f"[1/1] Connecting to native TCP {host}:{port}...")
            with socket.create_connection((host, port), timeout=15):
                pass
            print("[link-flow] native TCP connect: OK")
        else:
            raise fail("scheme", f"unsupported scheme: {scheme}", 4)
        print("[link-flow] complete")
        return 0
    except FlowError as error:
        print(f"[link-flow][ERROR][{error.stage}] {error}")
        return error.exit_code
    except (OSError, ValueError) as error:
        print(f"[link-flow][ERROR][runtime] {error}")
        return 5


if __name__ == "__main__":
    raise SystemExit(main())
