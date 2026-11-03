#!/usr/bin/env python3
"""Assemble the Linux client/server release zip.

Works like package-windows.ps1: extracts the base asset archive, overlays the
freshly built binaries, config and every supported weapon's current assets,
then re-zips everything into a single distributable archive.

Uses only the Python standard library, so it runs on any Linux box with
python3 — no zip/unzip CLI needed. The version number is read from the
VERSION file in the repo root and appended to the output archive name.

Usage:
  ./package-linux.py [--skip-build] [--assets <zip>] [--output <zip>]

NOTE: the Linux client links libglfw.so.3 dynamically, so the target machine
must have libglfw3 installed (e.g. `sudo apt install libglfw3`). Unlike the
Windows build there is no static GLFW link.
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import time
import zipfile

ROOT = os.path.dirname(os.path.abspath(__file__))


def add_to_zip(zf, full_path, rel_path):
    """Write one file into the archive, preserving the executable bit."""
    info = zipfile.ZipInfo(rel_path)
    info.compress_type = zipfile.ZIP_DEFLATED
    info.date_time = time.localtime(os.path.getmtime(full_path))[:6]
    mode = 0o100755 if os.access(full_path, os.X_OK) else 0o100644
    info.external_attr = mode << 16
    with open(full_path, "rb") as fh:
        zf.writestr(info, fh.read())


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Assemble the Linux client/server release zip.",
        epilog="NOTE: the client links libglfw.so.3 dynamically; targets need libglfw3 installed.",
    )
    parser.add_argument("--skip-build", action="store_true", help="reuse existing binaries in bin/")
    parser.add_argument("--assets", default=None,
                        help="base asset archive (default: Krodin-Linux.zip; accepts the legacy KrunkNative-Linux.zip seed)")
    parser.add_argument("--output", default=None,
                        help="output archive (default: Krodin-Linux-<version>.zip)")
    args = parser.parse_args()

    asset_archive = os.path.abspath(args.assets) if args.assets else os.path.join(ROOT, "Krodin-Linux.zip")
    if args.assets is None and not os.path.isfile(asset_archive):
        legacy_archive = os.path.join(ROOT, "KrunkNative-Linux.zip")
        if os.path.isfile(legacy_archive):
            asset_archive = legacy_archive

    version_file = os.path.join(ROOT, "VERSION")
    if not os.path.isfile(version_file):
        print(f"error: missing version file: {version_file}", file=sys.stderr)
        return 1
    with open(version_file, encoding="utf-8") as fh:
        version = fh.read().strip()
    if not version:
        print(f"error: VERSION file is empty: {version_file}", file=sys.stderr)
        return 1

    output_archive = os.path.abspath(args.output) if args.output else os.path.join(ROOT, f"Krodin-Linux-{version}.zip")

    if not os.path.isfile(asset_archive):
        print(f"error: missing asset archive: {asset_archive}", file=sys.stderr)
        return 1

    if not args.skip_build:
        result = subprocess.run(["make", "-C", ROOT, "client", "server"])
        if result.returncode != 0:
            print(f"error: build failed with exit code {result.returncode}", file=sys.stderr)
            return result.returncode

    client_bin = os.path.join(ROOT, "bin", "krodin_client")
    server_bin = os.path.join(ROOT, "bin", "krodin_server")
    for required in (client_bin, server_bin):
        if not os.path.isfile(required):
            print(f"error: missing binary: {required}", file=sys.stderr)
            return 1

    stage = tempfile.mkdtemp(prefix="Krodin-package-")
    try:
        with zipfile.ZipFile(asset_archive) as zf:
            zf.extractall(stage)
        for name in ("krunknative_client", "krunknative_server"):
            legacy_binary = os.path.join(stage, name)
            if os.path.isfile(legacy_binary):
                os.remove(legacy_binary)

        overlays = [
            (client_bin, "krodin_client"),
            (server_bin, "krodin_server"),
            (os.path.join(ROOT, "assets/config/game.toml"), "assets/config/game.toml"),
            (os.path.join(ROOT, "assets/shaders/basic.frag"), "assets/shaders/basic.frag"),
            (os.path.join(ROOT, "assets/textures/objective_4.png"), "assets/textures/objective_4.png"),
            (os.path.join(ROOT, "assets/textures/objective_5.png"), "assets/textures/objective_5.png"),
        ]
        for name in sorted(os.listdir(os.path.join(ROOT, "assets/maps"))):
            if name.endswith(".json"):
                rel = "assets/maps/" + name
                overlays.append((os.path.join(ROOT, rel), rel))
        obsolete_sandstorm = os.path.join(stage, "assets/maps/sandstorm.json")
        if os.path.isfile(obsolete_sandstorm):
            os.remove(obsolete_sandstorm)
        # The archive seed can contain old files under the same model names.
        with open(os.path.join(ROOT, "assets/config/weapon-assets.txt"), encoding="utf-8") as fh:
            for line in fh:
                asset = line.strip()
                if asset and not asset.startswith("#"):
                    rel = "assets/" + asset
                    overlays.append((os.path.join(ROOT, rel), rel))
        # Hosted map art is not included in mod.zip or older seed archives.
        with open(os.path.join(ROOT, "assets/config/map-assets.txt"), encoding="utf-8") as fh:
            for line in fh:
                asset = line.strip()
                if asset and not asset.startswith("#"):
                    rel = "assets/" + asset
                    overlays.append((os.path.join(ROOT, rel), rel))
        for source, rel in overlays:
            if not os.path.isfile(source):
                print(f"error: missing package input: {source}", file=sys.stderr)
                return 1
            dest = os.path.join(stage, rel)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            shutil.copy2(source, dest)

        if os.path.exists(output_archive):
            os.remove(output_archive)

        with zipfile.ZipFile(output_archive, "w", zipfile.ZIP_DEFLATED) as zf:
            for base, _dirs, files in os.walk(stage):
                for name in files:
                    full = os.path.join(base, name)
                    add_to_zip(zf, full, os.path.relpath(full, stage))

        print(f"Created {output_archive}")
    finally:
        shutil.rmtree(stage, ignore_errors=True)

    return 0


if __name__ == "__main__":
    sys.exit(main())
