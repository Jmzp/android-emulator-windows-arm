# Android Emulator for Windows on ARM

**English** · [Español](README.es.md)

Run a real Android 13 device **natively** on Windows on ARM laptops (Surface Pro, Snapdragon X), with `adb` connected and ready for React Native, Expo, Flutter or Kotlin development.

<p align="center">
  <img src="docs/images/expo-app.png" alt="Expo app running in the emulator window" width="260">
  &nbsp;
  <img src="docs/images/android-home.png" alt="Android home screen" width="260">
  &nbsp;
  <img src="docs/images/about-device.png" alt="About phone: Android 13, LineageOS 20 arm64" width="260">
</p>
<p align="center"><sub>An Expo app with Fast Refresh, the Android home screen, and "About phone". All three are real captures from a Surface Pro.</sub></p>

---

## Why this exists

If you develop mobile apps on an ARM laptop running Windows, you've probably hit this wall:

- Google's Android Emulator doesn't run on Windows ARM64.
- Microsoft retired the Windows Subsystem for Android in March 2025.
- Third-party emulators are built for gamers, not for `adb` and Metro.

This project fills that gap. Android runs in a [Waydroid](https://waydro.id) container inside WSL2. Your machine is ARM and Android is ARM, so nothing gets emulated: apps run at native CPU speed. One command starts it, and Windows sees a regular `adb` device.

## Highlights

- **Native arm64.** No instruction translation. The Snapdragon cores run Android code directly.
- **One command or one double-click.** It boots Android, opens a phone-sized window and connects `adb`. The "Allow USB debugging?" prompt never shows up.
- **Made for development.** It works with `adb`, Metro, Expo Go, Fast Refresh and `adb reverse` out of the box.
- **Resource caps.** RAM and CPU are limited (4 GB / 4 cores by default), so your IDE and browser stay responsive.
- **Reversible.** One flag puts back the stock WSL kernel. Nothing is installed on Windows itself, apart from WSL settings and an optional desktop shortcut.

## Tested on

| | |
|---|---|
| Device | Surface Pro, Snapdragon X Plus (8 cores), 16 GB RAM |
| OS | Windows 11 Home ARM64, build 26300 |
| WSL | 2.6.3, WSLg 1.0.71, kernel 6.6.87.2 (+ binder) |
| Android | Waydroid 1.6.2, LineageOS 20 (Android 13, API 33), `arm64_only` image |
| Verified with | `adb`, Expo SDK 58 / Expo Go, Fast Refresh, touch input |

Other Snapdragon X machines (X Elite, X Plus, X2) should behave the same way. If you try one, please share how it went.

## Quick start

You need Windows 11 on ARM, WSL 2 (`wsl --version`), `adb.exe` from the Android SDK platform-tools, and about 10 GB of free disk space. Run everything from PowerShell at the repo root:

```powershell
.\windows\setup-wsl.ps1        # 1. Ubuntu 24.04 arm64 in WSL, with systemd          (~3 min)
.\windows\configure-wsl.ps1    # 2. Caps WSL at 4 GB RAM / 4 cores                   (instant)
.\windows\install-kernel.ps1   # 3. Builds and enables a WSL kernel with binder      (20-60 min, once)
.\windows\android.ps1 setup    # 4. Installs Waydroid and downloads Android (~800 MB) (10-20 min)
.\windows\create-shortcut.ps1  # 5. Optional: "Android Emulator" icon on the desktop
```

Then start it:

```powershell
.\windows\android.ps1 start
```

```text
==> Opening phone window (432x936)
==> Starting Waydroid session
==> Showing Android
==> Waiting for Android to boot
==> adb bridge: 0.0.0.0:5555 -> 192.168.240.112:5555
adb key authorized.
connected to 172.22.97.155:5555
==> Ready: 172.22.97.155:5555  WayDroid arm64 only Device (arm64-v8a)
    Use it with: $env:ANDROID_SERIAL = '172.22.97.155:5555'
```

> [!NOTE]
> Steps 2 and 3 edit `%USERPROFILE%\.wslconfig` (a backup goes to `.wslconfig.bak` the first time) and restart WSL. **Every** WSL distro uses the custom kernel, Docker Desktop included. The kernel is Microsoft's own, plus binder, so Docker keeps working.

> [!IMPORTANT]
> `setup-wsl.ps1` creates a user with passwordless `sudo` **inside the Ubuntu distro** (`/etc/sudoers.d/90-android-wsl`). That's what lets the Windows scripts drive WSL without stopping at a password prompt.

Want the Play Store? Use `.\windows\android.ps1 setup -Gapps` instead, then [register the device with Google](https://www.google.com/android/uncertified).

## Daily use

```powershell
.\windows\android.ps1 start                  # phone-sized window (432x936)
.\windows\android.ps1 start -Window 480x1040 # any size you like
.\windows\android.ps1 start -Full            # use the whole WSLg window
.\windows\android.ps1 status                 # Waydroid state + adb devices
.\windows\android.ps1 stop                   # shut Android down and free the RAM
```

Or just double-click **Android Emulator** on your desktop. A console opens, boots Android, connects `adb` and prints the serial. You can close that console afterwards: Android keeps running until you run `stop`.

> [!TIP]
> The serial is `<WSL IP>:5555`, and the WSL IP can change whenever WSL restarts. `start` always prints the current one.

### React Native / Expo

```powershell
.\windows\android.ps1 start
.\windows\rn-connect.ps1                      # adb reverse for Metro (8081) and Expo (19000-19002)
$env:ANDROID_SERIAL = '<serial printed by start>'

npx expo start --android                      # Expo Go (installed automatically the first time)
npx expo run:android                          # or a development build
npx react-native run-android                  # or bare React Native
```

Fast Refresh works as on any device. Save a file and the screen updates without losing state. `adb reverse` rules are cleared when Android restarts, so run `rn-connect.ps1` again after each `start`.

### Flutter, Android Studio and other tools

Anything that talks to `adb` sees the device: `adb devices`, `flutter devices`, `flutter run -d <serial>`, `./gradlew installDebug`, and Android Studio's device picker. Only the Expo / React Native flow has been verified end to end so far. Reports for other tools are welcome.

## How it works

```
Windows 11 ARM64
 └─ WSL2 VM ─ Ubuntu 24.04 arm64, custom kernel with binder
     ├─ Weston (nested, kiosk shell) ── a phone-sized window on your desktop via WSLg
     │   └─ Waydroid ─ LXC container running LineageOS 20 (Android 13, arm64)
     └─ socat :5555 ──► Android's adbd  ◄── adb.exe on Windows (via the WSL IP)
```

Each piece solves one specific problem:

| Problem | Solution |
|---|---|
| WSL's kernel has no **binder**, Android's IPC | [`build-kernel.sh`](wsl/kernel/build-kernel.sh) builds Microsoft's kernel at the same version, plus [`waydroid.config`](wsl/kernel/waydroid.config) (binder, iptables tables for the container's network) |
| WSLg always maximizes the Waydroid window | Android draws inside a nested **Weston** in kiosk mode, sized like a phone |
| With systemd, WSL shuts the distro down when no `wsl.exe` is attached | A hidden `wsl.exe … sleep infinity` keeps it alive. It's launched through WMI, so closing the console doesn't kill it |
| Background processes die with the `wsl.exe` that started them | Weston, the session, the UI and the adb bridge run as **systemd user units** with lingering enabled |
| WSL's `localhost` forwarding is unreliable with systemd | `adb` connects to the distro's IP instead, through a `socat` bridge |
| The "Allow USB debugging?" prompt blocks automation | `start` pre-authorizes your Windows `adbkey.pub` inside Android |
| No GPU passthrough for Waydroid's Mesa on WSL | Rendering uses ANGLE + SwiftShader (software). That's plenty for app UIs |

## Configuration

### RAM and CPU

Android lives inside the WSL VM, so the VM limits in `.wslconfig` are the real limits. They are caps, not reservations: memory Android isn't using goes back to Windows (`autoMemoryReclaim=dropCache`).

```powershell
.\windows\configure-wsl.ps1                            # default: 4 GB, 4 cores, 4 GB swap
.\windows\configure-wsl.ps1 -MemoryGB 6 -Processors 6  # more headroom
```

Android 13 uses about 2–3 GB at idle, so 4 GB is comfortable for development. If you rebuild the kernel, raise it to 6 GB or more for the duration: the link step is memory-hungry.

### Screen size and density

The window size is the screen size Android sees. The default 432×936 at density 180 behaves like a ~384×832 dp phone. You can change it per launch (`-Window 480x1040`) or simulate other devices inside the same window:

```powershell
adb shell wm density 160        # fit more content (or 200 for bigger UI)
adb shell wm size 1080x2340     # different logical resolution, scaled to the window
adb shell wm size reset; adb shell wm density reset
```

### Environment variables

| Variable (Windows) | Default | Purpose |
|---|---|---|
| `ANDROID_WSL_DISTRO` | `Ubuntu-24.04` | WSL distro that hosts Android |
| `ANDROID_WSL_ADB_PORT` | `5555` | Port of the adb bridge inside WSL |

Android system properties live in the `[properties]` section of `/var/lib/waydroid/waydroid.cfg`, which [`setup-waydroid.sh`](wsl/setup-waydroid.sh) initializes. Run `sudo waydroid upgrade --offline` after editing them.

## Project structure

```
windows/                     PowerShell, run from Windows
  setup-wsl.ps1              Install and prepare the Ubuntu distro
  configure-wsl.ps1          RAM / CPU / swap limits for WSL
  install-kernel.ps1         Build + enable the binder kernel (-Revert to undo)
  android.ps1                setup | start | stop | status
  rn-connect.ps1             adb reverse for Metro / Expo
  create-shortcut.ps1        Desktop shortcut with icon
  common.ps1                 Shared helpers
wsl/                         Bash, runs inside the distro
  kernel/build-kernel.sh     Clone + configure + build the WSL kernel
  kernel/waydroid.config     Kconfig fragment (binder, netfilter)
  setup-waydroid.sh          Install Waydroid, download Android, set properties
  start-android.sh           Weston + session + UI + adb bridge (systemd user units)
  stop-android.sh            Stop all of the above
  authorize-adb.sh           Trust a Windows adb key inside Android
assets/                      Shortcut icon
docs/images/                 Screenshots
```

## Troubleshooting

Everything Android-related runs as systemd user units inside the distro (`waydroid-weston`, `waydroid-session`, `waydroid-ui`, `waydroid-adb-bridge`). Start with the logs:

```bash
wsl -d Ubuntu-24.04
journalctl --user -u waydroid-session -u waydroid-ui -u waydroid-weston
sudo waydroid logcat -b crash       # Android crashes
sudo tail /var/lib/waydroid/waydroid.log
```

**Kernel and WSL**

| Symptom | Fix |
|---|---|
| `binder is not available` | `wsl -d Ubuntu-24.04 -- uname -r` must end in `-waydroid`. If it doesn't, check `kernel=` in `.wslconfig` and run `wsl --shutdown`. |
| The kernel build stops with no error, and WSL "restarts" every ~90 s | Something was OOM-killed, and systemd (`OOMPolicy=stop`) keeps stopping everything started from `wsl.exe`. Run `wsl --shutdown`, raise RAM with `configure-wsl.ps1`, then build again. The build is incremental. |
| `CONFIG_... did not end up =y` | The kernel branch changed its dependencies. Look at `make menuconfig` in `~/wsl-kernel-build/WSL2-Linux-Kernel`. |
| WSL updated to a new kernel version | Nothing breaks, because your kernel keeps loading. To track the new version, run `install-kernel.ps1` again. |
| Scripts hang and `wsl -l -v` doesn't answer | The WSL service is stuck. Run `wsl --shutdown --force` (close stray `wsl.exe` processes first if needed), then `android.ps1 start`. |

**Android and Waydroid**

| Symptom | Fix |
|---|---|
| `waydroid-net.sh` fails with `table mangle does not exist` | Your kernel predates the netfilter options. Run `install-kernel.ps1` again with the current `waydroid.config`. |
| Black screen, and `system_server` crashes in `getCompositionColorSpaces` | The compositor rejected the buffer size. Don't set `persist.waydroid.width/height`: the window size (`-Window`) controls it. |
| Android shuts down on its own | The hidden keep-alive `wsl.exe` is gone. Run `android.ps1 start` again. |
| No internet inside Android | `sudo waydroid container restart`, then check that `sudo iptables -t nat -L` has rules for `waydroid0`. |

**adb**

| Symptom | Fix |
|---|---|
| `adb connect` refused | `waydroid status` must show `RUNNING` with an IP, and `systemctl --user status waydroid-adb-bridge` must be active. |
| `failed to authenticate` | You regenerated `%USERPROFILE%\.android\adbkey`. Run `android.ps1 start` again to trust the new key. |
| Device shows as `offline` | Android was stopped or WSL restarted. Run `android.ps1 start`; the serial may have changed. |

## Limitations

- **Not an AVD.** Android Studio's Device Manager doesn't manage it. It appears as a network-connected device.
- **Software rendering.** Fine for app UIs and development, but not for games or heavy 3D.
- **One Android version.** LineageOS 20 (Android 13, API 33). You can't switch API levels the way you can with AVD images.
- **arm64 apps only.** Snapdragon X chips can't run 32-bit ARM code, so Waydroid uses the `arm64_only` image. x86 or `armeabi-v7a`-only apps won't install. React Native and Expo builds include `arm64-v8a` by default.
- **The serial can change** after WSL restarts, because it's based on the WSL IP.

## Uninstall

```powershell
.\windows\android.ps1 stop
.\windows\install-kernel.ps1 -Revert           # back to Microsoft's stock WSL kernel
wsl --unregister Ubuntu-24.04                  # deletes the distro and everything in it
Remove-Item "$env:USERPROFILE\wsl-kernel" -Recurse
Remove-Item "$([Environment]::GetFolderPath('Desktop'))\Android Emulator.lnk"
```

To restore your previous WSL limits, copy `%USERPROFILE%\.wslconfig.bak` back over `.wslconfig`.

## Credits

- [Waydroid](https://waydro.id) runs Android in a Linux container.
- [LineageOS](https://lineageos.org) provides the Android images Waydroid uses.
- [Microsoft WSL2-Linux-Kernel](https://github.com/microsoft/WSL2-Linux-Kernel) is the kernel this project extends with binder.
- [Weston](https://gitlab.freedesktop.org/wayland/weston) provides the nested, phone-sized window.

## License

[MIT](LICENSE). The scripts in this repo are MIT-licensed. Waydroid, LineageOS and the Linux kernel keep their own licenses, and the kernel you build locally is GPL-2.0.
