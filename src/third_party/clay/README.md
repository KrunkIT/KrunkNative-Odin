# Clay

This directory vendors the official Odin bindings, implementation header, and
native Windows/Linux libraries for [Clay](https://github.com/nicbarker/clay).
The exact upstream revision is recorded in `UPSTREAM_COMMIT`; Clay's license is
in `LICENSE.md`.

`clay.c` is the implementation translation unit used to rebuild the native
library from the pinned `clay.h`. The Windows library is built with MSVC and
`CLAY_DISABLE_SIMD`, then archived with `lib.exe` because Odin's Windows linker
expects a library archive. The Linux library is the upstream prebuilt archive.
