"""Bounded live comparison of idle, PONG, and input traffic using the Python transport.

Usage: python counter_probe.py <invite> --traffic idle|pong|input --seconds 20
Only protocol metadata is printed; assignment credentials stay private.
"""
import argparse
import contextlib
import io
import os
import select
import time

import link_flow as flow
from krunker_msgpack import decode_packets, encode_packets


def probe(url, options):
    stream, buffered = flow._raw_open_ws(url)
    started = time.monotonic()
    counter = 0
    sent = 0
    sequence = 13
    spawned = False
    failed = False

    def send(message):
        nonlocal counter, sent
        if message[0] != "cptR":
            counter = (counter + options.increment) & 255
        flow._raw_send_frame(stream, encode_packets([message], counter))
        sent += 1
        if sent <= 16 or sent % 120 == 0:
            print(f"[counter-probe] SEND n={sent} opcode={message[0]} counter={counter}", flush=True)

    bootstrap = []
    bootstrap_at = 0
    live_at = None
    next_input = 0
    try:
        stream.settimeout(5)
        deadline = started + options.seconds
        while time.monotonic() < deadline:
            now = time.monotonic()
            if bootstrap and now >= bootstrap_at:
                send(bootstrap.pop(0))
                bootstrap_at = now + 0.5
                if not bootstrap:
                    live_at = bootstrap_at
                    next_input = live_at
            if live_at is not None and now >= next_input and options.traffic != "idle":
                if options.traffic == "pong":
                    send(["v"])
                else:
                    controls = {f"0-{i}": -1 if i == 4 else 0 for i in range(4, 15)}
                    send(["q", 0, sequence, [34], 0, [0, -4712], controls])
                    sequence += 1
                next_input = now + 1 / 30
            if not buffered and not stream.pending() and not select.select([stream], [], [], 0.005)[0]:
                continue
            opcode, payload, buffered = flow._raw_recv_frame(stream, buffered)
            if opcode == 8:
                print(f"[counter-probe] CLOSE at={now-started:.2f}s payload={payload.hex()} sent={sent}", flush=True)
                failed = True
                break
            if opcode == 9:
                flow._raw_send_frame(stream, payload, opcode=10)
                continue
            if opcode != 2:
                continue
            _, messages = decode_packets(payload)
            for message in messages:
                if not isinstance(message, list) or not message:
                    continue
                kind = message[0]
                if kind == "load" and sent == 0:
                    send(["load"])
                elif kind == "ready" and message[1]:
                    bootstrap = flow.initial_player_messages()
                    bootstrap_at = time.monotonic()
                elif kind == "start":
                    spawned = True
                    print(f"[counter-probe] SPAWN at={now-started:.2f}s", flush=True)
                elif kind == "l" and options.traffic != "idle":
                    send(["v"])
                elif kind in {"error", "dc", "f", "fe"}:
                    print(f"[counter-probe] SERVER at={now-started:.2f}s {message!r}", flush=True)
                    if kind in {"error", "dc"}:
                        failed = True
        print(f"[counter-probe] RESULT traffic={options.traffic} increment={options.increment} spawned={spawned} failed={failed} seconds={time.monotonic()-started:.2f} sent={sent}", flush=True)
        return not failed and spawned
    finally:
        stream.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("link")
    parser.add_argument("--traffic", choices=["idle", "pong", "input"], default="idle")
    parser.add_argument("--seconds", type=float, default=20)
    parser.add_argument("--increment", type=int, default=37)
    options = parser.parse_args()
    flow.load_dotenv()
    os.environ.setdefault("KRUNKER_TEAM", "2")
    os.environ.setdefault("KRUNKER_CLASS", "2")
    # Reuse invite resolution while suppressing its legacy credential output.
    assigned = []
    flow.messagepack_probe = lambda url, *_args: assigned.append(url)
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            flow.run_browser_invite(flow.parse_link(options.link), packet_probe=True, spawn=True, stay=True)
        return 0 if probe(assigned[0], options) else 1
    except flow.FlowError as error:
        print(f"[counter-probe] ERROR stage={error.stage} (credential-bearing response omitted)")
        return error.exit_code


if __name__ == "__main__":
    raise SystemExit(main())
