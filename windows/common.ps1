# Shared settings for the Windows-side scripts. Dot-source it: . "$PSScriptRoot\common.ps1"

# The Ubuntu release that gets installed, and the name it is registered under
# (ANDROID_WSL_DISTRO lets you keep it apart from an Ubuntu you already use).
$BaseDistro = 'Ubuntu-24.04'
$Distro   = if ($env:ANDROID_WSL_DISTRO) { $env:ANDROID_WSL_DISTRO } else { $BaseDistro }
$AdbPort  = if ($env:ANDROID_WSL_ADB_PORT) { [int]$env:ANDROID_WSL_ADB_PORT } else { 5555 }
$RepoRoot = Split-Path $PSScriptRoot -Parent
$KernelDir = Join-Path $env:USERPROFILE 'wsl-kernel'
# GitHub repo whose Releases hold the prebuilt kernels (see build-kernel.yml).
$ReleaseRepo = if ($env:ANDROID_WSL_RELEASE_REPO) { $env:ANDROID_WSL_RELEASE_REPO } else { 'Jmzp/android-emulator-windows-arm' }
$WslConfig = Join-Path $env:USERPROFILE '.wslconfig'

# Make wsl.exe's own messages (wsl -l, --status) UTF-8 instead of UTF-16.
$env:WSL_UTF8 = '1'

function Test-DistroInstalled {
    $names = (& wsl.exe -l -q) -replace "`0", '' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    return $names -contains $Distro
}

function ConvertTo-WslPath([string]$WindowsPath) {
    $full = [IO.Path]::GetFullPath($WindowsPath)
    '/mnt/' + $full.Substring(0, 1).ToLower() + ($full.Substring(2) -replace '\\', '/')
}

# Runs a repo script inside the distro as the default user.
function Invoke-RepoScript([string]$RelativePath, [string[]]$Arguments = @()) {
    $path = ConvertTo-WslPath (Join-Path $RepoRoot $RelativePath)
    & wsl.exe -d $Distro --cd '~' -- bash $path @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$RelativePath failed (exit $LASTEXITCODE)" }
}

# adb only auto-detects emulators on odd ports 5555-5585 of 127.0.0.1.
if ($AdbPort -lt 5555 -or $AdbPort -gt 5585 -or $AdbPort % 2 -eq 0) {
    throw "ANDROID_WSL_ADB_PORT must be an odd port between 5555 and 5585 (got $AdbPort)"
}

# The adb bridge listens on IPv4 inside WSL, which WSL forwards to the Windows
# 127.0.0.1, so adb lists the device as a regular emulator with a fixed serial.
function Get-AndroidSerial { "emulator-$($AdbPort - 1)" }

# A running adb server only scans emulator ports when it starts. Real emulators
# announce themselves by sending "host:emulator:<adb port>" to it; do the same.
function Register-Emulator([string]$Adb) {
    & $Adb start-server 2>$null | Out-Null
    $msg = "host:emulator:$AdbPort"
    $client = [Net.Sockets.TcpClient]::new()
    try {
        $client.Connect('127.0.0.1', 5037)
        $bytes = [Text.Encoding]::ASCII.GetBytes(('{0:x4}{1}' -f $msg.Length, $msg))
        $client.GetStream().Write($bytes, 0, $bytes.Length)
    } catch {
        Write-Warning "Could not register with the adb server: $_"
    } finally { $client.Dispose() }
}

function Get-WslIp {
    ((& wsl.exe -d $Distro -- hostname -I) -split '\s+' | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1)
}

# Window size in pixels and Android density (dpi). The size Android apps see,
# in dp, is pixels * 160 / dpi: phone 384x832, small 360x640, pixel 412x915
# (a Pixel 7), tablet 1280x800 (smallest width 800dp, so tablet layouts kick in).
$DeviceProfiles = [ordered]@{
    phone  = @{ Window = '432x936';  Density = 180 }
    small  = @{ Window = '405x720';  Density = 180 }
    pixel  = @{ Window = '412x915';  Density = 160 }
    tablet = @{ Window = '1280x800'; Density = 160 }
}

# Where Windows-side state lives (the last start options, used by rotate).
$StateDir = Join-Path $env:LOCALAPPDATA 'android-wsl'

# Metro (8081) and the Expo dev server ports.
$DefaultReversePorts = @(8081, 19000, 19001, 19002)

# Lets the app reach servers on Windows' localhost, as on a regular emulator.
function Set-AdbReverse([string]$Adb, [string]$Serial, [int[]]$Ports = $DefaultReversePorts) {
    foreach ($p in $Ports) { & $Adb -s $Serial reverse "tcp:$p" "tcp:$p" | Out-Null }
}

function Get-Adb {
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
    if (Test-Path $sdk) { return $sdk }
    throw 'adb.exe not found. Install Android SDK platform-tools or add adb to PATH.'
}
