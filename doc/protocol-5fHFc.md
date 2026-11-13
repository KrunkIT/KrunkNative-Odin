# Protocol reference: build 5fHFc

Captured from the official site on 2026-11-13 with the existing source extractor.
The capture remains under `logs/protocol-current/`; it needs no account login and
blocks matchmaking during extraction.

Raw source SHA-256:
`b266970d38efdc1f76f0221e7695cc97d9568075906d991d9717845555c69604`.

The socket starts its outbound counter at zero. Every normal send runs this
operation (variable names simplified):

```js
counter = (counter + 0x43e1) & 0xff;
```

`cptR` preserves the counter. The two trailer bytes remain the high and low
nibbles. The effective increment is 225, giving first trailers `0e 01`, `0c 02`,
`0a 03`, `08 04`, `06 05`, `04 06`, `02 07`, `00 08`, `0e 09`.
The preceding build's increment of 37 is incompatible.

The `en` MessagePack array has 13 elements including the opcode. Its loadout at
index 1 has 35 elements, ending with `titleIndex` (default -1). Indexes 2 and 3
remain the literal integers 16 and 18. Six boolean flags follow, then an optional
header at index 10 and two final boolean flags. The native client previously
sent 34 loadout elements and an extra trailing boolean.

Tests cover entry structure and the counter across 600 interleaved control/input
packets, including wraps and the `cptR` exception. The connection log reports
`protocol_build=5fHFc counter_increment=225` so live tests identify the codec in use.
