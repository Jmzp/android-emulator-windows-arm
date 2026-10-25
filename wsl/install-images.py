#!/usr/bin/env python3
"""Installs (or switches) Waydroid's Android images quickly.

    install-images.py VANILLA|GAPPS OWNER/REPO|official

Waydroid downloads images over one HTTP connection, and SourceForge caps each
connection at ~200-300 KB/s, so ~1 GB can take over an hour. For each image
(system, vendor) this picks:

  1. the GitHub mirror (see mirror-android-images.yml), when it has this
     architecture and type: GitHub is fast over a single connection;
  2. otherwise the official channel, downloaded with 16 parallel connections
     (aria2c, ~15x faster), checked against the official SHA-256 and kept in
     CACHE_DIR, so switching back to it later needs no download.

Pre-downloaded zips are handed to `waydroid init` through a throwaway OTA
channel on 127.0.0.1. Afterwards waydroid.cfg points at the real channels
again, so `waydroid upgrade` keeps working.
"""
import functools
import glob
import hashlib
import http.server
import json
import os
import subprocess
import sys
import tempfile
import threading
import urllib.request

OFFICIAL = "https://ota.waydro.id"
CFG = "/var/lib/waydroid/waydroid.cfg"
CACHE_DIR = os.path.expanduser("~/.cache/android-wsl/images")


def host_arch():
    sys.path.insert(0, "/usr/lib/waydroid")
    from tools.helpers import arch
    return arch.host()


def fetch_json(url):
    try:
        with urllib.request.urlopen(url, timeout=30) as r:
            return json.load(r)
    except Exception:
        return None


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def download_parallel(entry):
    """Returns a verified local copy of the zip described by an OTA entry."""
    os.makedirs(CACHE_DIR, exist_ok=True)
    path = os.path.join(CACHE_DIR, entry["filename"])
    if os.path.exists(path) and sha256(path) == entry["id"]:
        print(f"==> Using cached {entry['filename']}", flush=True)
        return path
    print(f"==> Downloading {entry['filename']} ({entry['size'] / 1e6:.0f} MB, 16 connections)", flush=True)
    # SourceForge's /download URL redirects to a mirror; resolve it once so
    # every connection hits the same server.
    final = subprocess.run(["curl", "-fsIL", "-o", "/dev/null", "-w", "%{url_effective}", entry["url"]],
                           check=True, capture_output=True, text=True).stdout
    subprocess.run(["aria2c", "-x16", "-s16", "-k1M", "--file-allocation=none", "--allow-overwrite=true",
                    "--auto-file-renaming=false", "--console-log-level=warn", "--summary-interval=15",
                    "-d", CACHE_DIR, "-o", entry["filename"], final], check=True)
    if sha256(path) != entry["id"]:
        os.remove(path)
        sys.exit(f"SHA-256 mismatch for {entry['filename']}")
    # Keep only the newest zip of each kind (same name apart from the date).
    kind = entry["filename"].split("-", 2)[2]
    for old in glob.glob(os.path.join(CACHE_DIR, "*")):
        if old != path and old.endswith(kind):
            os.remove(old)
    return path


def main():
    system_type, repo = sys.argv[1], sys.argv[2]
    arch = host_arch()
    # Where waydroid looks for each image's channel file, under a channel base.
    rel = {"system": f"lineage/waydroid_{arch}/{system_type}.json", "vendor": f"waydroid_{arch}/MAINLINE.json"}
    mirror = f"https://raw.githubusercontent.com/{repo}/ota"

    base = {}   # kind -> channel base URL that waydroid.cfg ends up with
    local = {}  # kind -> (OTA entry, local zip) to serve from 127.0.0.1
    for kind in ("system", "vendor"):
        if repo != "official" and fetch_json(f"{mirror}/{kind}/{rel[kind]}"):
            print(f"==> {kind} image: GitHub mirror", flush=True)
            base[kind] = f"{mirror}/{kind}"
            continue
        base[kind] = f"{OFFICIAL}/{kind}"
        channel = fetch_json(f"{base[kind]}/{rel[kind]}")
        if not channel:
            sys.exit(f"Could not read {base[kind]}/{rel[kind]}")
        print(f"==> {kind} image: official channel, parallel download", flush=True)
        local[kind] = (channel["response"][0], download_parallel(channel["response"][0]))

    init_base = dict(base)
    serve_dir = tempfile.mkdtemp(prefix="android-wsl-ota-")
    server = None
    if local:
        handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=serve_dir)
        handler.log_message = lambda *a: None
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        local_url = f"http://127.0.0.1:{server.server_port}"
        for kind, (entry, zip_path) in local.items():
            os.symlink(zip_path, os.path.join(serve_dir, entry["filename"]))
            channel_file = os.path.join(serve_dir, kind, rel[kind])
            os.makedirs(os.path.dirname(channel_file), exist_ok=True)
            with open(channel_file, "w") as f:
                json.dump({"response": [dict(entry, url=f"{local_url}/{entry['filename']}")]}, f)
            init_base[kind] = f"{local_url}/{kind}"

    try:
        subprocess.run(["sudo", "waydroid", "init", "-f", "-s", system_type,
                        "-c", init_base["system"], "-v", init_base["vendor"]], check=True)
    finally:
        if server:
            server.shutdown()
        subprocess.run(["rm", "-rf", serve_dir])

    # Point waydroid.cfg back at the real channels. The saved datetimes match
    # them, so `waydroid upgrade` only downloads genuinely newer images.
    fix = (f"import configparser\n"
           f"c = configparser.ConfigParser(); c.optionxform = str; c.read({CFG!r})\n"
           f"c['waydroid']['system_ota'] = {base['system'] + '/' + rel['system']!r}\n"
           f"c['waydroid']['vendor_ota'] = {base['vendor'] + '/' + rel['vendor']!r}\n"
           f"c.write(open({CFG!r}, 'w'))\n")
    subprocess.run(["sudo", "python3", "-c", fix], check=True)


if __name__ == "__main__":
    main()
