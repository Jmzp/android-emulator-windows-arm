# Shared settings for the Windows-side scripts. Dot-source it: . "$PSScriptRoot\common.ps1"

$Distro   = if ($env:ANDROID_WSL_DISTRO) { $env:ANDROID_WSL_DISTRO } else { 'Ubuntu-24.04' }
$AdbPort  = if ($env:ANDROID_WSL_ADB_PORT) { [int]$env:ANDROID_WSL_ADB_PORT } else { 5555 }
$RepoRoot = Split-Path $PSScriptRoot -Parent
$KernelDir = Join-Path $env:USERPROFILE 'wsl-kernel'
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

# WSL's localhost forwarding is unreliable with systemd distros, so adb
# connects to the distro's own IP (it changes on every WSL restart).
function Get-AndroidSerial {
    $ip = ((& wsl.exe -d $Distro -- hostname -I) -split '\s+' | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1)
    if (-not $ip) { throw "Could not get the IP of $Distro" }
    "${ip}:$AdbPort"
}

function Get-Adb {
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
    if (Test-Path $sdk) { return $sdk }
    throw 'adb.exe not found. Install Android SDK platform-tools or add adb to PATH.'
}
