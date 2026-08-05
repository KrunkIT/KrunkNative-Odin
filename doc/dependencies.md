# Dependencies: C version vs Odin port

The original KrunkNative was written in C and vendored several third-party libraries. The Odin
port (`src/`) replaces nearly all of them with Odin's `vendor/` bindings and `core/` stdlib.

## Old C Dependencies

| Library | Vendored at | Provided |
|---|---|---|
| GLFW | `client/lib/glfw` | windowing, input, OpenGL context |
| GLAD | `client/lib/glad` | OpenGL loader |
| FreeType | `client/lib/freetype` | font rasterizer |
| STB Image | `client/include/stb_image.h` + `client/src/stb_image.c` | image loading |
| fast_obj | `client/include/fast_obj.h` + `client/src/fast_obj.c` | OBJ model loading |
| verstable | `shared/include/verstable.h` | open-addressing hash table |
| cJSON | `shared/lib/cJSON` | JSON parsing |
| pcg_basic | `shared/lib/pcg_basic` | pseudorandom number generator |
| replxx | `server/lib/replxx` | server REPL line editing |

To build GLFW from source, the old C README also required these Debian packages:

```
libwayland-dev wayland-protocols pkg-config libx11-dev libxcursor-dev libxinerama-dev
libxrandr-dev libxi-dev libgl1-mesa-dev libglu1-mesa-dev libxkbcommon-dev
```

## Odin Vendor Packages

| Package | Replaces |
|---|---|
| `vendor:glfw` | GLFW |
| `vendor:OpenGL` | GLAD (GL entry points loaded at runtime, no link-time dependency) |
| `vendor:stb/image` | STB Image |
| `vendor:stb/truetype` | FreeType |

## Odin Stdlib Packages

| Package | Replaces |
|---|---|
| `core:encoding/json` | cJSON |
| `core:math/rand` | pcg_basic |
| `core:fmt` | replxx output / C `printf` |
| `core:net` | raw POSIX/WinSock sockets (new) |
| `core:math/linalg` | hand-written vec/matrix structs (new) |
| `core:mem` | manual `malloc`/`free` (new) |
| `core:strconv` | TOML parsing (new) |

## Replaced Without a Package

| C library | Odin replacement |
|---|---|
| fast_obj | hand-written `parse_obj` in `src/client/geometry.odin:81` |
| verstable | Odin built-in `map` types (e.g. `g_geometry_cache`, `g_glyph_cache`) |
| replxx | plain `core:fmt` output (no interactive line editing) |
