# Live gameplay packets

The live WebSocket adapter decodes packets in `src/krunker`; client projection
and presentation live in `src/client/krunker_*.odin`. State never borrows strings
or arrays from the temporary MessagePack decoder. Unknown opcodes are ignored.
Schemas were checked against the browser receiver in `game.deob.js`, including
its game-state enum, objective loader, and mode-specific leaderboard layouts.

| Packets | Behavior |
| --- | --- |
| `init` | Initial scores, round wins, clock, lockout, objective, movement lock, optional game state; resets previous match state. Config `tmSize` (0–3) sets 1–4 roster slots per team, independently of total `maxPlayers`/spectator slots. |
| `ts`, `t`, `lkt`, `gsc` | Team scores, server clock, warmup countdown, match phase. End-screen countdowns do not replace the game clock. |
| `gmsg` | Waiting for players, warmup, match-start and intermission countdowns. Repeated labels refresh their server time. Breaks pause the match/objective clocks and never consume the next objective's duration. |
| `obj`, `uobj`, `wep` | Objective UID/timer, occupant count, objective weapon ID. Objective weapons are separate from player loadout slots. |
| `tm` | Confirmed player team, including the local lobby assignment. |
| `lm`, `ulm`, `chgp` | Movement lock/unlock and explicit position resets. Teleports address socket IDs; resets discard obsolete prediction. |
| `end`, `rds` | End result, final team totals, round/sides transitions. Round wins accept the browser's string-keyed map. Normal final END counts its winning round once; abnormal endings do not award a round. Ends active lives and prevents late movement snapshots from respawning players. |
| `4`, `5`, `6`, `7` | Hit confirmation, score changes, local kills, leaderboard statistics. String and numeric combat opcodes are accepted. |
| `noc`, `frz`, `spb`, `unl` | Noclip, frozen movement/combat, speed multiplier, unlimited ammunition in live prediction. |
| `p`, `mp`, `lv` | Interaction progress, manual progress/display flag, remaining lives. |
| `pr`, `pre`, `ex` | Standard weapon projectiles, removal by server SID or local projectile shot counter, bounded explosion flashes. Presentation never applies live damage. |
| `fe` | Entry rejection, including an empty packet, clears the pending request and permits retry after a short throttle. A late rejection cannot interrupt an active life. |

The HUD displays round wins and current/total rounds at the top center, with
the next-objective countdown below. Current objective point totals sit below
the match timer. Both score displays work even when an objective UID cannot
be resolved locally. Lobby capacity fields and localized server notices (`chi`)
are logged to diagnose mismatched roster sizes and server entry rejections.

Existing ownership, lobby, roster, snapshots, ammunition, health, tracer, and
death/disconnect handling remains in place. Death counts now reach native player
state. Local deaths disable entry for the browser's 2.8-second death delay.
START waits for fresh spawn coordinates; a roster received before START also
works. Previous-life prediction and ACKs cannot move the camera to the death
position during this handoff.

Leaderboard schemas currently cover FFA, TDM, Hardpoint, CTF, Gun Game, Classic
FFA, Kill Confirmed, Sharp Shooter, Team Defender, Carrier, Chaos Snipers, and
Impulsed. Other mode layouts are ignored rather than interpreting a statistic
as the wrong field. `uobj` carries an occupant count, **not a team ID**; it does
not establish which team owns the point.

The remaining protocol work includes dynamic map-object UID mapping and
movement/destruction, zone/flag/domination modes, scripted/custom projectiles,
AI/entities, inventory/pickups, chat/social/store/cosmetics, and script events.
The native map importer does not yet reproduce the browser's game-object
namespace; raw map indices must not be used for `do`, `ro`, or `objmv`.
Explosion flashes use the existing glow texture; the browser's particle and
audio effects are not reproduced in full.

Validation: `odin test src/client -define:ODIN_TEST_THREADS=1`, plus the native
simulation suite. Tests include malformed input, joining mid-match, long-lived
match state, objective IDs, authoritative team changes, prediction flags,
teleports, death/round transitions, projectile ID namespaces, and rendered
explosion lifetime. No authenticated live match was used for this verification.
