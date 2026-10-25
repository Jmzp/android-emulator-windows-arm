#!/usr/bin/env python3
"""Records the Android screen to an MP4.

    record.py OUTPUT.mp4 SECONDS [STOP_FILE]

Android's own `screenrecord` hangs in Waydroid (this image's mediaserver
waits forever for an OMX codec service it doesn't ship), so this grabs raw
frames with `screencap` in a loop (~14 fps at 432x936) and encodes them with
ffmpeg at a constant 15 fps. Recording stops after SECONDS or as soon as
STOP_FILE exists.
"""
import os
import shutil
import struct
import subprocess
import sys
import threading
import time

FPS = 15
CAPTURE = ["sudo", "-n", "waydroid", "shell", "--", "sh", "-c", "while screencap; do :; done"]


def main():
    out, seconds = sys.argv[1], float(sys.argv[2])
    stop_file = sys.argv[3] if len(sys.argv) > 3 else None
    if stop_file and os.path.exists(stop_file):
        os.remove(stop_file)

    if not shutil.which("ffmpeg"):
        print("==> Installing ffmpeg (first recording only)", flush=True)
        subprocess.run(["sudo", "DEBIAN_FRONTEND=noninteractive", "apt-get", "install", "-y", "-qq", "ffmpeg"],
                       check=True, stdout=subprocess.DEVNULL)

    cap = subprocess.Popen(CAPTURE, stdout=subprocess.PIPE)
    # Raw screencap: width, height, pixel format, color space (uint32 each), then RGBA pixels.
    width, height, fmt, _ = struct.unpack("<4I", cap.stdout.read(16))
    if fmt != 1:
        sys.exit(f"Unexpected screencap pixel format {fmt} (expected RGBA_8888)")
    size = width * height * 4

    latest = [cap.stdout.read(size)]
    done = threading.Event()

    def reader():
        while not done.is_set():
            if len(cap.stdout.read(16)) < 16:
                break
            frame = cap.stdout.read(size)
            if len(frame) < size:
                break
            latest[0] = frame

    threading.Thread(target=reader, daemon=True).start()

    enc = subprocess.Popen(
        ["ffmpeg", "-loglevel", "error", "-y",
         "-f", "rawvideo", "-pix_fmt", "rgba", "-s", f"{width}x{height}", "-r", str(FPS), "-i", "-",
         "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2", "-c:v", "libx264", "-preset", "veryfast",
         "-crf", "23", "-pix_fmt", "yuv420p", "-movflags", "+faststart", out],
        stdin=subprocess.PIPE)

    # Write the newest frame on a fixed clock so the video plays in real time
    # even though screencap's frame rate varies.
    start = time.monotonic()
    frames = 0
    try:
        while time.monotonic() - start < seconds:
            if stop_file and os.path.exists(stop_file):
                break
            enc.stdin.write(latest[0])
            frames += 1
            delay = start + frames / FPS - time.monotonic()
            if delay > 0:
                time.sleep(delay)
    except KeyboardInterrupt:
        pass
    finally:
        done.set()
        cap.terminate()
        subprocess.run(["sudo", "-n", "waydroid", "shell", "--", "pkill", "-f", "while screencap"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        enc.stdin.close()
        enc.wait()
        if stop_file and os.path.exists(stop_file):
            os.remove(stop_file)
    print(f"==> Recorded {frames / FPS:.1f} s ({width}x{height})", flush=True)
    sys.exit(enc.returncode)


if __name__ == "__main__":
    main()
