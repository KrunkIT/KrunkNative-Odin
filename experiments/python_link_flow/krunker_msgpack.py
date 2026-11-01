"""Minimal MessagePack and Krunker packet framing helpers.

Krunker packets are one or more concatenated MessagePack values followed by
two nibble bytes. The suffix is an 8-bit ahNum value, not a checksum:
``bytes(((ah_num >> 4) & 0xF, ah_num & 0xF))``.
"""

from __future__ import annotations

import struct
from typing import Any


class MessagePackError(ValueError):
    pass


def _length_prefix(length: int, fix_base: int, type_byte: int) -> bytes:
    if length < 16:
        return bytes((fix_base | length,))
    if length < 256:
        return bytes((type_byte, length))
    if length < 65536:
        return bytes((type_byte + 1,)) + struct.pack(">H", length)
    return bytes((type_byte + 2,)) + struct.pack(">I", length)


def pack(value: Any) -> bytes:
    if value is None:
        return b"\xc0"
    if value is False:
        return b"\xc2"
    if value is True:
        return b"\xc3"
    if isinstance(value, int) and not isinstance(value, bool):
        if 0 <= value < 128:
            return bytes((value,))
        if -32 <= value < 0:
            return bytes((value & 0xFF,))
        if 0 <= value < 256:
            return b"\xcc" + struct.pack(">B", value)
        if 0 <= value < 65536:
            return b"\xcd" + struct.pack(">H", value)
        if 0 <= value < 2**32:
            return b"\xce" + struct.pack(">I", value)
        if 0 <= value < 2**64:
            return b"\xcf" + struct.pack(">Q", value)
        if -128 <= value < 128:
            return b"\xd0" + struct.pack(">b", value)
        if -32768 <= value < 32768:
            return b"\xd1" + struct.pack(">h", value)
        if -2**31 <= value < 2**31:
            return b"\xd2" + struct.pack(">i", value)
        if -2**63 <= value < 2**63:
            return b"\xd3" + struct.pack(">q", value)
        raise MessagePackError(f"integer out of range: {value}")
    if isinstance(value, float):
        return b"\xcb" + struct.pack(">d", value)
    if isinstance(value, str):
        encoded = value.encode("utf-8")
        if len(encoded) < 32:
            return bytes((0xA0 | len(encoded),)) + encoded
        if len(encoded) < 256:
            return b"\xd9" + struct.pack(">B", len(encoded)) + encoded
        if len(encoded) < 65536:
            return b"\xda" + struct.pack(">H", len(encoded)) + encoded
        return b"\xdb" + struct.pack(">I", len(encoded)) + encoded
    if isinstance(value, (bytes, bytearray, memoryview)):
        encoded = bytes(value)
        if len(encoded) < 256:
            return b"\xc4" + struct.pack(">B", len(encoded)) + encoded
        if len(encoded) < 65536:
            return b"\xc5" + struct.pack(">H", len(encoded)) + encoded
        return b"\xc6" + struct.pack(">I", len(encoded)) + encoded
    if isinstance(value, (list, tuple)):
        if len(value) < 16:
            prefix = bytes((0x90 | len(value),))
        elif len(value) < 65536:
            prefix = b"\xdc" + struct.pack(">H", len(value))
        else:
            prefix = b"\xdd" + struct.pack(">I", len(value))
        return prefix + b"".join(pack(item) for item in value)
    if isinstance(value, dict):
        if len(value) < 16:
            prefix = bytes((0x80 | len(value),))
        elif len(value) < 65536:
            prefix = b"\xde" + struct.pack(">H", len(value))
        else:
            prefix = b"\xdf" + struct.pack(">I", len(value))
        return prefix + b"".join(pack(k) + pack(v) for k, v in value.items())
    raise MessagePackError(f"unsupported value type: {type(value).__name__}")


class _Reader:
    def __init__(self, data: bytes):
        self.data = data
        self.offset = 0

    def take(self, count: int) -> bytes:
        end = self.offset + count
        if end > len(self.data):
            raise MessagePackError("truncated MessagePack value")
        value = self.data[self.offset:end]
        self.offset = end
        return value

    def byte(self) -> int:
        return self.take(1)[0]

    def value(self) -> Any:
        marker = self.byte()
        if marker <= 0x7F:
            return marker
        if marker >= 0xE0:
            return marker - 256
        if 0xA0 <= marker <= 0xBF:
            return self.take(marker & 0x1F).decode("utf-8")
        if 0x90 <= marker <= 0x9F:
            return [self.value() for _ in range(marker & 0x0F)]
        if 0x80 <= marker <= 0x8F:
            return {self.value(): self.value() for _ in range(marker & 0x0F)}
        if marker == 0xC0:
            return None
        if marker == 0xC2:
            return False
        if marker == 0xC3:
            return True
        if marker == 0xC4:
            return self.take(struct.unpack(">B", self.take(1))[0])
        if marker == 0xC5:
            return self.take(struct.unpack(">H", self.take(2))[0])
        if marker == 0xC6:
            return self.take(struct.unpack(">I", self.take(4))[0])
        if marker == 0xCA:
            return struct.unpack(">f", self.take(4))[0]
        if marker == 0xCB:
            return struct.unpack(">d", self.take(8))[0]
        if marker in (0xCC, 0xCD, 0xCE, 0xCF):
            sizes = {0xCC: (">B", 1), 0xCD: (">H", 2), 0xCE: (">I", 4), 0xCF: (">Q", 8)}
            fmt, size = sizes[marker]
            return struct.unpack(fmt, self.take(size))[0]
        if marker in (0xD0, 0xD1, 0xD2, 0xD3):
            sizes = {0xD0: (">b", 1), 0xD1: (">h", 2), 0xD2: (">i", 4), 0xD3: (">q", 8)}
            fmt, size = sizes[marker]
            return struct.unpack(fmt, self.take(size))[0]
        if marker in (0xD9, 0xDA, 0xDB):
            sizes = {0xD9: (">B", 1), 0xDA: (">H", 2), 0xDB: (">I", 4)}
            fmt, size = sizes[marker]
            return self.take(struct.unpack(fmt, self.take(size))[0]).decode("utf-8")
        if marker in (0xDC, 0xDD):
            sizes = {0xDC: (">H", 2), 0xDD: (">I", 4)}
            fmt, size = sizes[marker]
            return [self.value() for _ in range(struct.unpack(fmt, self.take(size))[0])]
        if marker in (0xDE, 0xDF):
            sizes = {0xDE: (">H", 2), 0xDF: (">I", 4)}
            fmt, size = sizes[marker]
            return {self.value(): self.value() for _ in range(struct.unpack(fmt, self.take(size))[0])}
        raise MessagePackError(f"unsupported MessagePack marker 0x{marker:02x}")


def unpack_one(data: bytes) -> tuple[Any, int]:
    reader = _Reader(data)
    value = reader.value()
    return value, reader.offset


def encode_trailer(ah_num: int) -> bytes:
    if not 0 <= ah_num <= 255:
        raise ValueError("ah_num must be an unsigned byte")
    return bytes(((ah_num >> 4) & 0x0F, ah_num & 0x0F))


def decode_trailer(data: bytes) -> int:
    if len(data) != 2 or data[0] > 0x0F or data[1] > 0x0F:
        raise MessagePackError("invalid two-byte Krunker trailer")
    return (data[0] << 4) | data[1]


def encode_packets(messages: list[Any], ah_num: int) -> bytes:
    return b"".join(pack(message) for message in messages) + encode_trailer(ah_num)


def decode_packets(data: bytes) -> tuple[int, list[Any]]:
    if len(data) < 3:
        raise MessagePackError("packet is too short")
    ah_num = decode_trailer(data[-2:])
    payload = data[:-2]
    messages: list[Any] = []
    offset = 0
    while offset < len(payload):
        value, consumed = unpack_one(payload[offset:])
        if consumed <= 0:
            raise MessagePackError("decoder consumed no bytes")
        messages.append(value)
        offset += consumed
    if not messages:
        raise MessagePackError("packet has no MessagePack values")
    return ah_num, messages


class AhNum:
    """Live-server counter, verified against the reference hoster's nibble rule."""

    def __init__(self, value: int = 0):
        self.value = value & 0xFF

    def for_opcode(self, opcode: str) -> int:
        if opcode != "cptR":
            self.value = (self.value + 37) & 0xFF
        return self.value

    def encode(self, message: list[Any]) -> bytes:
        if not message or not isinstance(message[0], str):
            raise MessagePackError("Krunker messages must begin with an opcode string")
        return encode_packets([message], self.for_opcode(message[0]))


class HosterAhNum:
    """Counter used by the reference Rust hoster for live-server comparison."""

    def __init__(self) -> None:
        self.x, self.y = 2, 5

    def encode(self, message: list[Any]) -> bytes:
        if not message or not isinstance(message[0], str):
            raise MessagePackError("Krunker messages must begin with an opcode string")
        value = (self.x << 4) | self.y
        if message[0] != "cptR":
            if self.y + 5 >= 16:
                self.x = (self.x + 3) & 0x0F
            else:
                self.x = (self.x + 2) & 0x0F
            self.y = (self.y + 5) & 0x0F
        return encode_packets([message], value)
