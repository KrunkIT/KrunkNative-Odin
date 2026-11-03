#!/usr/bin/env python3
"""Refresh the official map catalog from GAPI (Python standard library only)."""

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import json
import os
from pathlib import Path
import tempfile
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parent
MAP_NAMES = (
    "Burg", "Littletown", "Sandstorm", "Subzero", "Undergrowth", "Shipment",
    "Freight", "Lostworld", "Citadel", "Oasis", "Kanji", "Industry", "Lumber",
    "Evacuation", "Site", "SkyTemple", "Lagoon", "Bureau", "Tortuga", "Tropicano",
    "Krunk_Plaza", "Arena", "Habitat", "Atomic", "Old_Burg", "Throwback",
    "Stockade", "Facility", "Clockwork", "Laboratory", "Shipyard", "Soul Sanctum",
    "Bazaar", "Erupt", "HQ", "Khepri", "Lush", "Vivo", "Slide Moonlight",
    "Eterno Simulator", "Stalk Factory", "Eterno_jump", "Frontier", "Bastion",
    "Piazza", "Barnyard", "Candy Heist",
)


def map_slug(name):
    return name.lower().replace(" ", "_")


def map_filename(map_id):
    # Retain the existing native Sandstorm alias and its regression fixtures.
    return "sandstorm_v3" if map_id == 2 else map_slug(MAP_NAMES[map_id])


def fetch_json(url, timeout=30):
    for attempt in range(3):
        try:
            request = Request(url, headers={"User-Agent": "Krodin-map-downloader/1.0", "Accept": "application/json"})
            with urlopen(request, timeout=timeout) as response:
                return json.load(response)
        except (HTTPError, URLError, TimeoutError) as error:
            if isinstance(error, HTTPError) and error.code < 500 and error.code != 429:
                raise
            if attempt == 2:
                raise
            time.sleep(attempt + 1)


def validate_map(response, map_id):
    data = response.get("data") if isinstance(response, dict) else None
    if not isinstance(data, dict):
        raise ValueError(f"map {map_id}: response has no map data")
    if not isinstance(data.get("objects"), list) or not isinstance(data.get("spawns"), list):
        raise ValueError(f"map {map_id}: missing objects/spawns arrays")
    if not data["objects"] or not data["spawns"]:
        raise ValueError(f"map {map_id}: empty objects/spawns arrays")
    if not isinstance(data.get("name"), str) or not data["name"]:
        raise ValueError(f"map {map_id}: missing map name")
    return data


def atomic_write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    handle, temporary = tempfile.mkstemp(prefix=path.name + ".", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(handle, "wb") as stream:
            stream.write(content)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def update_map(map_id, output, base_url):
    url = f"{base_url.rstrip('/')}/{map_id}"
    data = validate_map(fetch_json(url), map_id)
    target = output / (map_filename(map_id) + ".json")
    content = (json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")
    status = "added"
    if target.exists():
        try:
            existing = json.loads(target.read_text(encoding="utf-8"))
        except (ValueError, UnicodeError):
            existing = None
        status = "unchanged" if existing == data else "replaced"
    if status != "unchanged":
        atomic_write(target, content)
    # The old Sandstorm export has the same public name but obsolete geometry.
    # Remove it only after the replacement downloaded and validated successfully.
    if map_id == 2:
        duplicate = output / "sandstorm.json"
        if duplicate.exists():
            duplicate.unlink()
    return {"id": map_id, "name": MAP_NAMES[map_id], "asset": target.stem, "source": url}, status


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ids", type=int, nargs="+", default=list(range(len(MAP_NAMES))), help="map IDs to refresh (default: 0-46)")
    parser.add_argument("--output", type=Path, default=ROOT / "assets/maps")
    parser.add_argument("--base-url", default="https://gapi.svc.krunker.io/maps")
    parser.add_argument("--workers", type=int, default=4)
    args = parser.parse_args(argv)
    if any(i < 0 or i >= len(MAP_NAMES) for i in args.ids):
        parser.error("map IDs must be between 0 and 46")
    if not 1 <= args.workers <= 8:
        parser.error("workers must be between 1 and 8")
    failures = []
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        jobs = {pool.submit(update_map, i, args.output, args.base_url): i for i in sorted(set(args.ids))}
        for future in as_completed(jobs):
            map_id = jobs[future]
            try:
                entry, status = future.result()
                print(f"{map_id:2d} {entry['name']}: {status}", flush=True)
            except Exception as error:
                failures.append(map_id)
                print(f"{map_id:2d} {MAP_NAMES[map_id]}: FAILED: {error}", flush=True)
    if failures:
        print("Failed map IDs: " + ", ".join(map(str, sorted(failures))))
        return 1
    print(f"Refreshed {len(set(args.ids))} maps in {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
