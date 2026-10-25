# Shared settings for the Windows-side scripts. Dot-source it: . "$PSScriptRoot\common.ps1"

$Distro   = if ($env:ANDROID_WSL_DISTRO) { $env:ANDROID_WSL_DISTRO } else { 'Ubuntu-24.04' }
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

function Get-WslIp {
    ((& wsl.exe -d $Distro -- hostname -I) -split '\s+' | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1)
}

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
