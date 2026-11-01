# Python link-flow experiment

This folder is an isolated experiment for the Krunker invite flow. It accepts
one link, loads KRUNKER_ACCESS_TOKEN from the environment or the repository
.env, resolves browser invites through the matchmaker, and performs the
assigned TLS/WebSocket upgrade.

Run it from this folder or the repository root:

```powershell
python experiments/python_link_flow/link_flow.py "https://krunker.io/?game=MBI:gn5o9"
```

The packet probe uses Python's standard library in this checkout. Optional
dependencies are not required:

```powershell
python -m pip install -r experiments/python_link_flow/requirements.txt
python experiments/python_link_flow/link_flow.py "https://krunker.io/?game=MBI:gn5o9" --packets
```

The command uses the built-in TLS and WebSocket probe either way, so packet
ordering stays identical across environments.

The probe waits for the server's initial `["load", ...]` announcement and then
sends the acknowledgement, whose live-server bytes are `91 A4 6C 6F 61 64 02 05`.
`--spawn` continues with `po`, `en`, team 1 selection (`cd`, `t`, `1`), class 2
selection (`cd`, `c`, `{c: 2, s: null}`), a second `en`, the compressed `q`
samples, and `v`. It stays connected until the server
sends `start` or `KRUNKER_SPAWN_TIMEOUT` expires (90 seconds by default). A
repeating `gmsg wt` means the server is waiting for the lobby's configured
minimum players; the client cannot bypass that server-side gate.

The two-byte ahNum trailer is a sequence/tag field. The live server requires
`(counter + 37) & 255` before normal sends (`cptR` is exempt), matching the
reference hoster's nibble counter. The archived deobfuscated client uses +3,
which spawns successfully but fails under sustained traffic. This probe's
original `--stay` stops sending application packets after bootstrap, so its
long connection lifetime did not validate the counter under ongoing traffic.
The script does not write or modify the token. Keep `.env` private.

Set `KRUNKER_TEAM=2` or `KRUNKER_CLASS=<index>` to change the selection, or
`KRUNKER_SEND_SB=1` to send the optional account/session announcement.
`KRUNKER_SPAWN_TIMEOUT` controls how long the probe waits for `start`.

Use `--stay` for the persistent test variant. It selects team 2 and class 2
(Run N Gun / SMG), then remains connected after `start` until Ctrl+C:

```powershell
python experiments/python_link_flow/link_flow.py `
  "https://krunker.io/?game=FRA:jprpa" --stay
```

For a bounded test with continuous traffic and snapshot replies:

```powershell
python experiments/python_link_flow/counter_probe.py `
  "https://krunker.io/?game=FRA:jprpa" --traffic input --seconds 25
```

`--traffic idle` reproduces the original stay pattern. `--traffic pong` sends
PONGs at approximately 30 Hz without continuous movement. `--increment 3`
or `--increment 31` tests the archived browser rules. Counter-probe output
omits assignment credentials.

Live comparison on 2026-11-01 in FRA:jprpa: idle +3 stayed spawned for 18 s
(12 sends); continuous PONG +3 and +31 both received INVALID VERSION at
about 8 s; PONG +37 stayed spawned for 25 s (444 sends); input +37 stayed
spawned for 25 s (446 sends) without a server error. These are bounded
compatibility checks, not a claim of indefinite connectivity.
