# Roadmap

Where this project is heading, ordered by impact versus effort. Ideas and pull requests are welcome. If you want to take one of these on, open an issue first so we can agree on the approach.

**Legend:** ✅ done · 🚧 in progress · ⬜ planned · 🔬 research

## Phase 1: polish what exists

| | Item | Why it matters |
|---|---|---|
| 🚧 | **Prebuilt kernels on GitHub Releases** | A GitHub Actions workflow builds the binder kernel on an arm64 runner, so installing takes seconds instead of a 20–60 min local build, and OOM-during-build problems disappear. |
| ⬜ | **Stable serial, detected as an emulator** | Add a tiny Windows-side relay on `127.0.0.1:5555` so `adb` lists the device as `emulator-5554`. It would no longer change when WSL restarts, and Android Studio, Expo and Flutter would treat it like any emulator, with no `ANDROID_SERIAL` or `adb connect`. |
| ⬜ | **One-step installer (`install.ps1`)** | Chain the setup steps with preflight checks (ARM64, WSL version, `adb`, disk space), safe to re-run. |
| ⬜ | **`android.ps1 doctor`** | Automated diagnosis: binder kernel, systemd, units, adb bridge, Android networking, stuck WSL service. Turns the troubleshooting table into a command. |
| ⬜ | **Automatic `adb reverse` on start** | Fold `rn-connect.ps1` into `start` (opt-out flag), so Metro works without an extra step. |

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
