#!/usr/bin/env python3
"""Mirrors Waydroid's Android images into a GitHub Release and writes OTA
channel files that point at it.

Waydroid's images come from SourceForge, which can crawl at ~200 KB/s; GitHub
Releases serve the same files at tens of MB/s. For each architecture and image
type this script takes the latest entry of Waydroid's official OTA channel,
uploads that zip to the release (once, after checking its SHA-256), and
writes the same channel layout into OUT_DIR with the download URL swapped:

    OUT_DIR/system/lineage/waydroid_<arch>/<TYPE>.json
    OUT_DIR/vendor/waydroid_<arch>/MAINLINE.json

The workflow publishes OUT_DIR on the `ota` branch, which is what
`waydroid init -c <...>/ota/system -v <...>/ota/vendor` reads.

Env: GITHUB_REPOSITORY, GH_TOKEN, ARCHES (default "arm64_only arm64"),
SYSTEM_TYPES (default "VANILLA"), PREVIOUS_DIR (last published channel files,
whose zips are kept one more round so in-flight installs don't break).
"""
import hashlib
import json
import os
import subprocess
import sys
import urllib.request

OFFICIAL = "https://ota.waydro.id"
TAG = "android-images"
VENDOR_TYPE = "MAINLINE"


def gh(*args, check=True):
    return subprocess.run(["gh", *args], check=check, capture_output=True, text=True)


def fetch_json(url):
    with urllib.request.urlopen(url, timeout=60) as r:
        return json.load(r)


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def channel_files(arches, system_types):
    for arch in arches:
        for t in system_types:
            yield f"system/lineage/waydroid_{arch}/{t}.json"
        yield f"vendor/waydroid_{arch}/{VENDOR_TYPE}.json"


def main():
    out_dir = sys.argv[1]
    repo = os.environ["GITHUB_REPOSITORY"]
    arches = os.environ.get("ARCHES", "arm64_only arm64").split()
    system_types = os.environ.get("SYSTEM_TYPES", "VANILLA").split()
    previous_dir = os.environ.get("PREVIOUS_DIR", "")

    if gh("release", "view", TAG, check=False).returncode != 0:
        gh("release", "create", TAG, "--title", "Android images (mirror)", "--notes",
           "Unmodified Waydroid / LineageOS images mirrored from the official Waydroid OTA "
           "channel (ota.waydro.id), so installs don't depend on SourceForge's speed. Each "
           "zip's SHA-256 matches the official channel. setup-waydroid.sh uses them through "
           "the OTA files on the `ota` branch.")
    assets = {a["name"] for a in json.loads(gh("release", "view", TAG, "--json", "assets").stdout)["assets"]}

    keep = set()
    for rel in channel_files(arches, system_types):
        latest = fetch_json(f"{OFFICIAL}/{rel}")["response"][0]
        name = latest["filename"]
        keep.add(name)
        if name in assets:
            print(f"up to date  {name}", flush=True)
        else:
            print(f"mirroring   {name} ({latest['size'] / 1e6:.0f} MB)", flush=True)
            subprocess.run(["curl", "-fL", "--retry", "5", "--retry-all-errors", "-sS",
                            "-o", name, latest["url"]], check=True)
            if sha256(name) != latest["id"]:
                sys.exit(f"SHA-256 mismatch for {name}")
            gh("release", "upload", TAG, name, "--clobber")
            os.remove(name)

        mirrored = dict(latest, url=f"https://github.com/{repo}/releases/download/{TAG}/{name}")
        path = os.path.join(out_dir, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            json.dump({"response": [mirrored]}, f, indent=4)

        if previous_dir:
            old = os.path.join(previous_dir, rel)
            if os.path.exists(old):
                keep.add(json.load(open(old))["response"][0]["filename"])

    for name in sorted(assets - keep):
        print(f"removing    {name}", flush=True)
        gh("release", "delete-asset", TAG, name, "--yes")


if __name__ == "__main__":
    main()
