# Changelog

## v0.0.2-alpha (unreleased)

The first substantive jump since v0.0.1-alpha: melee went from a stub to a
working weapon, bullet tracers and wall impacts landed, and the renderer got a
round of performance work.

### Added

- **Melee** — flat 50 damage matching the original, plus a shoulder-pivot
  swing that sweeps left↔right each attack with the knife gripped in the hand.
- **Bullet tracers** — instant full-length beams that fade in ~80 ms, plus wall
  impact decals.
- **Hardpoint round progression** — round resolution, score resets, and overtime
  sudden-death when the timer runs out on a tie.
- **FPS meter toggle** — show or hide the on-screen FPS counter from the settings
  panel.

### Changed

- **Physics** — ray-box collision now tests map geometry and separate body/head
  hitboxes.
- **Renderer** — shader uniform locations are cached, opaque scenes skip the
  depth sort, and the viewport is cached instead of queried every frame.
- **Fullscreen** — fullscreen mode now switches to the monitor's maximum
  resolution instead of defaulting to 1280x720.
- **Build** — `make PROFILE=minimal` and `make PROFILE=speed` optimization
  levels; default stays `none` for fast development builds.

### Known limitations

- Best-of-three match resolution is not wired up yet — rounds are best-of-one.
- SRM movement (dash, wall-dash) is not implemented.
- The Crossbow weapon is missing and knife throwing is still a stub.
- The simulation is not deterministic yet (unseeded RNG, no replay tests).
- Performance is a work in progress — build with `PROFILE=speed` for the best
  framerate.
