"""Windows side of the shared clipboard, run by clipboard-bridge.so.

Speaks the bridge's line protocol on stdin/stdout ("set <base64 UTF-8>"):
text read from stdin (Android copied it) goes to the Windows clipboard, and
whenever the Windows clipboard changes its text is written to stdout. Both
go through one long-lived PowerShell, because starting one per call takes
about a second.
"""
import base64
import os
import shutil
import subprocess
import sys
import threading
import time

POLL_SECONDS = 0.5

# Reads one command per line and answers each with one line; text travels
# as base64 so newlines and encodings survive the pipe.
SERVER = r"""
$utf8 = New-Object System.Text.UTF8Encoding $false
while ($null -ne ($line = [Console]::In.ReadLine())) {
    try {
        if ($line -eq 'get') {
            $text = Get-Clipboard -Raw
            if ($null -eq $text) { $text = '' }
            [Console]::Out.WriteLine([Convert]::ToBase64String($utf8.GetBytes($text)))
        } elseif ($line.StartsWith('set ')) {
            $text = $utf8.GetString([Convert]::FromBase64String($line.Substring(4)))
            if ($text) { Set-Clipboard -Value $text }
            [Console]::Out.WriteLine('ok')
        } else {
            [Console]::Out.WriteLine('ok')
        }
    } catch {
        [Console]::Out.WriteLine('')
    }
    [Console]::Out.Flush()
}
"""


def powershell_path():
    path = os.environ.get("ANDROID_WSL_POWERSHELL") or shutil.which("powershell.exe")
    return path or "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"


class WindowsClipboard:
    def __init__(self):
        self._lock = threading.Lock()
        self._proc = None

    def _call(self, line):
        with self._lock:
            for _ in range(2):  # restart PowerShell once if it died
                if self._proc is None or self._proc.poll() is not None:
                    encoded = base64.b64encode(SERVER.encode("utf-16-le")).decode()
                    self._proc = subprocess.Popen(
                        [powershell_path(), "-NoProfile", "-NonInteractive",
                         "-EncodedCommand", encoded],
                        stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        stderr=subprocess.DEVNULL, text=True, bufsize=1)
                try:
                    self._proc.stdin.write(line + "\n")
                    self._proc.stdin.flush()
                    reply = self._proc.stdout.readline()
                    if reply:
                        return reply.strip()
                except OSError:
                    pass
                self._proc = None
            return None

    def get(self):
        reply = self._call("get")
        if reply is None:
            return None
        return normalize(base64.b64decode(reply).decode(errors="replace"))

    def set(self, text):
        self._call("set " + base64.b64encode(text.encode()).decode())


def normalize(text):
    return text.replace("\r\n", "\n")


def main():
    clipboard = WindowsClipboard()
    last = clipboard.get()
    last_lock = threading.Lock()

    def send(text):
        sys.stdout.write("set " + base64.b64encode(text.encode()).decode() + "\n")
        sys.stdout.flush()

    # Android starts with whatever Windows has copied.
    if last:
        send(last)

    def from_android():
        nonlocal last
        for line in sys.stdin:
            if not line.startswith("set "):
                continue
            text = normalize(base64.b64decode(line[4:].strip()).decode(errors="replace"))
            # Under the lock, so a poll can't read the old text in between
            # and send it back over Android's copy.
            with last_lock:
                if text != last:
                    last = text
                    clipboard.set(text)
        os._exit(0)  # the compositor is gone

    threading.Thread(target=from_android, daemon=True).start()
    while True:
        time.sleep(POLL_SECONDS)
        with last_lock:
            text = clipboard.get()
            changed = text is not None and text != "" and text != last
            if changed:
                last = text
        if changed:
            send(text)


if __name__ == "__main__":
    main()
