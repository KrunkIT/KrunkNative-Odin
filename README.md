# KrunkNative (Odin)

Krunker.io - except it's awesome. A rewrite of the game, ported to **Odin**. The original native-C
implementation has been fully ported and removed; the entire engine lives in `src/` and is built
with Odin.

## Building

The port has one build toolchain: **Odin** (`make` is just a thin wrapper). There are no
third-party C libraries to fetch or compile — GLFW, OpenGL, and the image/font loaders come from
Odin's own `vendor/` bindings.

### Linux

Install the Odin compiler: <https://odin-lang.org>

```bash
sudo apt install pkg-config libglfw3 libglfw3-dev
```

That's the whole build-time dependency list. The old C-era README listed
`libwayland-dev`, `libx11-dev`, `libgl1-mesa-dev`, etc. — those are **not needed** by the Odin
port. They existed only to compile GLFW and GLAD from source; Odin's `vendor:glfw` binds the
pre-built system `libglfw.so.3` instead, and OpenGL entry points are loaded at **runtime**, so no
GL/Mesa/X11/Wayland development headers are required.

> **Fresh Odin installs only:** Odin ships the STB image/truetype libraries as source, and on
> Linux their prebuilt archives are generated locally. If `odin build` panics with
> *"Could not find the compiled STB libraries"*, run once:
>
> ```bash
> make -C "$(odin root)/vendor/stb/src"
> ```
>
> This needs a C compiler + `ar` (`build-essential` or gcc/clang + binutils).

Then:

```bash
make client   # bin/krunknative_client
make server   # bin/krunknative_server
make test     # build + run the simulation parity tests
```

### Windows

**Nothing to install.** Odin's `vendor:glfw` statically links the shipped `glfw3_mt.lib`
(no DLL needed), `vendor:stb` uses pre-shipped `.lib` files, and OpenGL is loaded at runtime.
You only need the Odin compiler and a working Windows linker (MSVC or MinGW-w64).

If you ever build the client with `-define:GLFW_SHARED=true`, copy
`$(odin root)/vendor/glfw/lib/glfw3.dll` next to the exe.

## Running

The client looks for the `assets` folder in the same directory in release mode, or in the parent
directory when run from `bin/` (development mode). See [the assets readme](/assets/README.md) for
how to add game assets.

```bash
./bin/krunknative_client                     # default map rotation
./bin/krunknative_client --map ss_v3         # select a specific map
./bin/krunknative_client --class hunter      # spawn as a specific class
./bin/krunknative_client --fps               # show the FPS meter
./bin/krunknative_client --help              # list maps and classes
./bin/krunknative_server                     # dedicated server (no dependencies)
```

You can also pick your class in-game on the class-select screen before spawning
(click a class, then click anywhere else to play).

## Runtime dependencies (Linux)

- `libglfw3` is the only required runtime library. It pulls in the X11/Wayland/GLX/EGL runtime
  libraries automatically on a desktop.
- For **headless/CI machines or software rendering**, also install `libgl1 libgl1-mesa-dri`
  (the client requests an OpenGL 4.5 core context, which Mesa's `llvmpipe` satisfies).
- OpenGL itself needs no package — the client loads every GL entry point at runtime via GLFW.

## Gameplay configuration

Weapons and classes are data-driven from `assets/config/game.toml` — named sections with partial
overrides over the built-in defaults:

The same file also controls the native server's competitive experiment: fixed tick rate, match
timer, objective rotation/scoring, regeneration delay, respawn delay, and score limit. The default
server runs at 64 Hz. The standard rotation is intentionally limited to `sandstorm`,
`undergrowth`, `industry`, and `evacuation`; all other bundled maps remain directly loadable with
`--map` or by custom server configuration. The normal class picker similarly uses the standard
nine-class pool while every class remains addressable with `--class` for custom play.

```toml
[weapons.ak47]
name = "Assault Rifle"
model = "mods/weapons/model/ak47.obj"
damage = 35.0

[classes.trooper]
loadout = ["ak47", "deagle", "knife"]
```

## Acknowledgements

- Odin - the language and stdlib (with vendor bindings for GLFW, OpenGL, and STB)
- KrunkNative C version - the original gameplay logic this port mirrors 1:1
- See [doc/dependencies.md](doc/dependencies.md) for how the Odin port replaced the C dependencies
