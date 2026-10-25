# Roadmap

Where this project is heading, ordered by impact versus effort. Ideas and pull requests are welcome. If you want to take one of these on, open an issue first so we can agree on the approach.

**Legend:** ✅ done · 🚧 in progress · ⬜ planned · 🔬 research

## Phase 1: polish what exists ✅

| | Item | Result |
|---|---|---|
| ✅ | **Prebuilt kernels on GitHub Releases** | A GitHub Actions workflow builds the binder kernel on an arm64 runner (~13 min) and publishes it. Installing takes ~10 seconds instead of a 20–60 min local build, and OOM-during-build problems are gone. |
| ✅ | **Android image mirror** | Waydroid's SourceForge downloads crawled at ~200 KB/s (a fresh install took 65 min). The images are now mirrored on GitHub Releases with a matching OTA channel, and a from-scratch install takes ~2 min. Validated end to end on a throwaway distro. |
| ✅ | **Stable serial, detected as an emulator** | No relay needed: the `socat` bridges listen on IPv4, which WSL forwards to Windows' `127.0.0.1:5555`, so `adb` auto-detects `emulator-5554`. A minimal console on port 5554 answers `adb emu avd name` / `kill`. Expo, React Native and Flutter pick it up with no `ANDROID_SERIAL` or `adb connect`. |
| ✅ | **One-step installer (`install.ps1`)** | Preflight checks (ARM64, Windows 11, WSL, `adb`, disk space), then every setup step. Re-running it takes ~12 s: finished steps are skipped and WSL isn't restarted. |
| ✅ | **`android.ps1 doctor`** | About 30 checks across Windows, WSL, kernel, Waydroid, systemd units, the adb bridge, Android networking and a hung WSL service, each with a fix. |
| ✅ | **Automatic `adb reverse` on start** | `start` reverses Metro (8081) and Expo (19000–19002); `-NoReverse` opts out, `rn-connect.ps1 -Ports` adds more. |

## Phase 2: developer experience 🚧

| | Item | Result / why it matters |
|---|---|---|
| ✅ | **Device profiles and rotation** | `-Device phone / small / pixel / tablet` sets window size and density together; `rotate` swaps portrait and landscape (a ~30 s restart, since the window can't resize while Android runs). |
| ✅ | **Snapshots and "wipe data"** | `snapshot save / restore / list / delete` keeps Android's user data (~100 MB); `wipe` gives a fresh first boot, like AVD's *Wipe Data*. |
| ✅ | **Screenshots and screen recording** | `screenshot` and `record` save into Pictures / Videos. Android's `screenrecord` hangs in Waydroid, so recording grabs `screencap` frames from WSL and encodes them with ffmpeg at 15 fps. |
| ✅ | **Easy APK install** | `android.ps1 install app.apk`, plus **Send to → Android Emulator** in Explorer's right-click menu. Dropping files on the window isn't possible: the nested Weston has no drag-and-drop to Android. |
| ⬜ | **Google Play services (GAPPS)** | Firebase Cloud Messaging, Google Sign-In, Maps and AdMob need Play services. Waydroid publishes a GAPPS `arm64_only` image; the work is a safe switch between VANILLA and GAPPS (keeping both images), a guided device registration with Google, and documenting what can't work (Play Integrity fails on an uncertified device). |
| ⬜ | **Shared clipboard** | Copy and paste between Windows and Android. WSLg syncs the clipboard, but the nested Weston likely cuts it off; needs research. |
| ⬜ | **Proper window title and icon** | The window says "Weston Compositor" and groups with WSL in the taskbar; it should read "Android Emulator". Weston's Wayland backend hardcodes the title. |

## Phase 3: research

| | Item | Why it matters |
|---|---|---|
| 🔬 | **GPU acceleration** | Rendering is software-only (SwiftShader). WSLg exposes the Adreno GPU through D3D12; investigate virgl/venus or a `d3d12` Mesa driver inside Waydroid. This is the biggest possible performance jump. |
| 🔬 | **More Android versions** | Offer newer LineageOS images (21+) as Waydroid ships them, to test across API levels. |
| 🔬 | **Audio, camera and location** | Audio is wired through WSLg's PulseAudio but untested. Location can be mocked with a mock-location app; camera needs research. |

## Phase 4: community and distribution 🚧

| | Item | Why it matters |
|---|---|---|
| ✅ | **CI quality checks** | [`lint.yml`](.github/workflows/lint.yml) runs `shellcheck`, `PSScriptAnalyzer` (rules in [`PSScriptAnalyzerSettings.psd1`](PSScriptAnalyzerSettings.psd1)) and a Python compile check on every push and pull request. |
| ⬜ | **System tray app** | A tray icon showing whether Android is on, with start / stop / copy serial; could ship through `winget`. |
| 🚧 | **Compatibility matrix** | Issue templates for bugs (asks for `doctor` output) and tested devices are in place; the matrix grows as reports from X Elite, X2 and Windows 11 Pro machines come in. |
| ✅ | **Demo GIF in the README** | A Fast Refresh clip recorded with `android.ps1 record` (22 KB). |
