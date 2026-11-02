#!/usr/bin/env python3
"""Restore Burg's hosted art, which is absent from Krunker's mod.zip.

27432g is a static, untextured glTF, converted to OBJ for the native renderer.
The conversion rejects animation, transforms and material changes rather than
silently flattening an unsupported future version. Uses only the standard library.
"""

import base64
import json
from pathlib import Path
import struct
from urllib.request import Request, urlopen
import zlib

from download_maps import atomic_write

ROOT = Path(__file__).resolve().parent
OBJ_IDS = (632, 2846, 30061, 30162, 61806, 61815, 61820)


def fetch(asset_id, filename):
    url = f"https://user-assets.krunker.io/{asset_id}/{filename}"
    request = Request(url, headers={"User-Agent": "Mozilla/5.0", "Referer": "https://krunker.io/"})
    with urlopen(request, timeout=30) as response:
        return response.read()


def convert_foliage(data):
    source = json.loads(data)
    if (source.get("animations") or source.get("skins") or source.get("images")
            or source.get("textures") or len(source["nodes"]) != 1
            or source["nodes"][0] != {"mesh": 0, "name": "Icosphere"}
            or len(source["meshes"]) != 1 or len(source["meshes"][0]["primitives"]) != 1):
        raise ValueError("27432 is no longer a single static, untextured identity mesh")
    primitive = source["meshes"][0]["primitives"][0]
    material = source["materials"][primitive["material"]]
    if (primitive.get("mode", 4) != 4 or primitive.get("targets")
            or material != {"doubleSided": True, "name": "Material.001",
                            "pbrMetallicRoughness": {"metallicFactor": 0, "roughnessFactor": 0.5}}):
        raise ValueError("27432 geometry or material changed; review before converting")

    def accessor(index):
        entry = source["accessors"][index]
        view = source["bufferViews"][entry["bufferView"]]
        uri = source["buffers"][view["buffer"]]["uri"]
        if not uri.startswith("data:application/octet-stream;base64,") or entry.get("sparse"):
            raise ValueError("expected an embedded, dense buffer")
        buffer = base64.b64decode(uri.split(",", 1)[1], validate=True)
        size = {"SCALAR": 1, "VEC2": 2, "VEC3": 3}[entry["type"]]
        code = {5123: "H", 5126: "f"}[entry["componentType"]]
        fmt = "<" + code * size
        offset = view.get("byteOffset", 0) + entry.get("byteOffset", 0)
        stride = view.get("byteStride", struct.calcsize(fmt))
        return [struct.unpack_from(fmt, buffer, offset + i * stride) for i in range(entry["count"])]

    positions = accessor(primitive["attributes"]["POSITION"])
    uvs = accessor(primitive["attributes"]["TEXCOORD_0"])
    indices = [entry[0] for entry in accessor(primitive["indices"])]
    if len(positions) != len(uvs) or len(indices) % 3 or max(indices) >= len(positions):
        raise ValueError("invalid foliage topology")
    lines = ["# Static conversion of https://user-assets.krunker.io/27432/model.gltf",
             "# Original coordinates; native registry preserves the glTF origin.", "o Icosphere"]
    lines.extend("v " + " ".join(format(v, ".9g") for v in point) for point in positions)
    lines.extend("vt " + " ".join(format(v, ".9g") for v in uv) for uv in uvs)
    for i in range(0, len(indices), 3):
        lines.append("f " + " ".join(f"{index+1}/{index+1}" for index in indices[i:i+3]))
    return ("\n".join(lines) + "\n").encode("ascii")


def white_png():
    # glTF's white default base color; each instance receives the map's ci tint.
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(b"\0\xff\xff\xff\xff")) + chunk(b"IEND", b""))


def main():
    pending = {}
    for asset_id in OBJ_IDS:
        model, texture = fetch(asset_id, "model.obj"), fetch(asset_id, "model.png")
        if b"\nv " not in model or b"\nf " not in model or not texture.startswith(b"\x89PNG\r\n\x1a\n"):
            raise ValueError(f"invalid OBJ/PNG for {asset_id}")
        pending[f"models/custom/{asset_id}.obj"] = model
        pending[f"textures/custom/{asset_id}.png"] = texture
        print(f"Fetched {asset_id}: {len(model)}B OBJ, {len(texture)}B PNG")
    source = fetch(27432, "model.gltf")
    pending["models/custom/27432.gltf"] = source
    pending["models/custom/27432.obj"] = convert_foliage(source)
    pending["textures/custom/27432.png"] = white_png()
    # Validate all downloads before replacing local files.
    for path, data in pending.items():
        target = ROOT / "assets" / path
        if not target.exists() or target.read_bytes() != data:
            atomic_write(target, data)
    print("Burg hosted assets restored")


if __name__ == "__main__":
    main()
