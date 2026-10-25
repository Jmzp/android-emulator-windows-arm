# Roadmap

Where this project is heading, ordered by impact versus effort. Ideas and pull requests are welcome. If you want to take one of these on, open an issue first so we can agree on the approach.

**Legend:** ✅ done · 🚧 in progress · ⬜ planned · 🔬 research

## Phase 1: polish what exists ✅

| | Item | Result |
|---|---|---|
| ✅ | **Prebuilt kernels on GitHub Releases** | A GitHub Actions workflow builds the binder kernel on an arm64 runner (~13 min) and publishes it. Installing takes ~10 seconds instead of a 20–60 min local build, and OOM-during-build problems are gone. |
| ✅ | **Stable serial, detected as an emulator** | No relay needed: the `socat` bridges listen on IPv4, which WSL forwards to Windows' `127.0.0.1:5555`, so `adb` auto-detects `emulator-5554`. A minimal console on port 5554 answers `adb emu avd name` / `kill`. Expo, React Native and Flutter pick it up with no `ANDROID_SERIAL` or `adb connect`. |
| ✅ | **One-step installer (`install.ps1`)** | Preflight checks (ARM64, Windows 11, WSL, `adb`, disk space), then every setup step. Re-running it takes ~12 s: finished steps are skipped and WSL isn't restarted. |
| ✅ | **`android.ps1 doctor`** | About 30 checks across Windows, WSL, kernel, Waydroid, systemd units, the adb bridge, Android networking and a hung WSL service, each with a fix. |
| ✅ | **Automatic `adb reverse` on start** | `start` reverses Metro (8081) and Expo (19000–19002); `-NoReverse` opts out, `rn-connect.ps1 -Ports` adds more. |

## Phase 2: developer experience

| | Item | Why it matters |
|---|---|---|
| ⬜ | **Device profiles and rotation** | Presets such as `-Device small` / `pixel` / `tablet` set window size and density in one go; `rotate` swaps portrait and landscape. |
| ⬜ | **Shared clipboard and drag-and-drop APK install** | Copy and paste between Windows and Android; drop an `.apk` on the window to install it. |
| ⬜ | **Snapshots and "wipe data"** | Back up and restore Android's data to get back to a clean state in seconds, like AVD's *Wipe Data*. |
| ⬜ | **Screenshot and screen-recording shortcuts** | Save `screencap` / `screenrecord` output straight into a Windows folder, handy for PRs and QA. |
| ⬜ | **Proper window title and icon** | The window says "Weston Compositor" and groups with WSL in the taskbar; it should read "Android Emulator". |

## Phase 3: research

| | Item | Why it matters |
|---|---|---|
| 🔬 | **GPU acceleration** | Rendering is software-only (SwiftShader). WSLg exposes the Adreno GPU through D3D12; investigate virgl/venus or a `d3d12` Mesa driver inside Waydroid. This is the biggest possible performance jump. |
| 🔬 | **More Android versions** | Offer newer LineageOS images (21+) as Waydroid ships them, to test across API levels. |
| 🔬 | **Audio, camera and location** | Audio is wired through WSLg's PulseAudio but untested. Location can be mocked with a mock-location app; camera needs research. |

## Phase 4: community and distribution

| | Item | Why it matters |
|---|---|---|
| ⬜ | **CI quality checks** | `shellcheck` for Bash and `PSScriptAnalyzer` for PowerShell on every pull request. |
| ⬜ | **System tray app** | A tray icon showing whether Android is on, with start / stop / copy serial; could ship through `winget`. |
| ⬜ | **Compatibility matrix** | Collect reports from Snapdragon X Elite, X2 and Windows 11 Pro machines, with issue templates for bugs and tested devices. |
| ⬜ | **Demo GIF in the README** | A short clip of opening the emulator and hot-reloading an app is the fastest way to show what this does. |
