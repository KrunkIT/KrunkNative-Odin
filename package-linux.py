#!/usr/bin/env python3
"""Assemble the Linux client/server release zip.

Works like package-windows.ps1: extracts the base asset archive, overlays the
freshly built binaries plus the repo-tracked config and Famas model/texture,
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
    parser.add_argument("--assets", default=os.path.join(ROOT, "KrunkNative-Linux.zip"),
                        help="base asset archive (default: KrunkNative-Linux.zip)")
    parser.add_argument("--output", default=None,
                        help="output archive (default: KrunkNative-Linux-<version>.zip)")
    args = parser.parse_args()

    asset_archive = os.path.abspath(args.assets)

    version_file = os.path.join(ROOT, "VERSION")
    if not os.path.isfile(version_file):
        print(f"error: missing version file: {version_file}", file=sys.stderr)
        return 1
    with open(version_file, encoding="utf-8") as fh:
        version = fh.read().strip()
    if not version:
        print(f"error: VERSION file is empty: {version_file}", file=sys.stderr)
        return 1

    output_archive = os.path.abspath(args.output) if args.output else os.path.join(ROOT, f"KrunkNative-Linux-{version}.zip")

    if not os.path.isfile(asset_archive):
        print(f"error: missing asset archive: {asset_archive}", file=sys.stderr)
        return 1

    if not args.skip_build:
        result = subprocess.run(["make", "-C", ROOT, "client", "server"])
        if result.returncode != 0:
            print(f"error: build failed with exit code {result.returncode}", file=sys.stderr)
            return result.returncode

    client_bin = os.path.join(ROOT, "bin", "krunknative_client")
    server_bin = os.path.join(ROOT, "bin", "krunknative_server")
    for required in (client_bin, server_bin):
        if not os.path.isfile(required):
            print(f"error: missing binary: {required}", file=sys.stderr)
            return 1

    stage = tempfile.mkdtemp(prefix="KrunkNative-package-")
    try:
        with zipfile.ZipFile(asset_archive) as zf:
            zf.extractall(stage)

        overlays = [
            (client_bin, "krunknative_client"),
            (server_bin, "krunknative_server"),
            (os.path.join(ROOT, "assets/config/game.toml"), "assets/config/game.toml"),
            (os.path.join(ROOT, "assets/models/weapons/weapon_15.obj"), "assets/models/weapons/weapon_15.obj"),
            (os.path.join(ROOT, "assets/textures/weapons/weapon_15.png"), "assets/textures/weapons/weapon_15.png"),
        ]
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
