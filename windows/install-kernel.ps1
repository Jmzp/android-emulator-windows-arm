<#
.SYNOPSIS
  Installs the binder-enabled WSL kernel and points %USERPROFILE%\.wslconfig
  at it. Restarts WSL (Docker Desktop included).

  By default it downloads the prebuilt kernel that matches your WSL kernel
  version from this repo's GitHub Releases (built by
  .github/workflows/build-kernel.yml) and verifies its SHA-256. If there is
  no release for your version, it builds locally instead.
.PARAMETER Build
  Build the kernel locally inside the distro (20-60 min) instead of downloading.
.PARAMETER Version
  Kernel version to download, e.g. 6.6.87.2. Defaults to the running WSL kernel.
.PARAMETER SkipBuild
  Reuse the Image already in %USERPROFILE%\wsl-kernel.
.PARAMETER Revert
  Remove the kernel= line and go back to Microsoft's stock kernel.
#>
param([switch]$Build, [string]$Version, [switch]$SkipBuild, [switch]$Revert)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"

function Set-WslConfigKernel([string]$Value) {
    $lines = if (Test-Path $WslConfig) { @(Get-Content $WslConfig) } else { @() }
    if ($lines.Count -and -not (Test-Path "$WslConfig.bak")) { Copy-Item $WslConfig "$WslConfig.bak" }

    $lines = @($lines | Where-Object { $_ -notmatch '^\s*kernel\s*=' })
    if ($Value) {
        $idx = [Array]::FindIndex([string[]]$lines, [Predicate[string]]{ param($l) $l -match '^\s*\[wsl2\]\s*$' })
        $entry = "kernel=$($Value -replace '\\', '\\')"
        if ($idx -ge 0) {
            $lines = @($lines[0..$idx]) + $entry + @(if ($idx + 1 -lt $lines.Count) { $lines[($idx + 1)..($lines.Count - 1)] })
        } else {
            $lines = @('[wsl2]', $entry) + $lines
        }
    }
    Set-Content -Path $WslConfig -Value $lines -Encoding ascii
}

# Returns the path of a verified download, or $null if no release exists.
function Get-PrebuiltKernel([string]$KernelVersion) {
    $base = "https://github.com/$ReleaseRepo/releases/download/kernel-$KernelVersion"
    $tmp = Join-Path ([IO.Path]::GetTempPath()) "wsl-kernel-$KernelVersion"
    New-Item -ItemType Directory -Force $tmp | Out-Null
    try {
        Invoke-WebRequest "$base/Image.sha256" -OutFile "$tmp\Image.sha256" -UseBasicParsing
    } catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 404) { return $null }
        throw
    }
    Write-Host "==> Downloading prebuilt kernel $KernelVersion from $ReleaseRepo"
    $ProgressPreference = 'SilentlyContinue'  # the progress bar makes downloads much slower
    Invoke-WebRequest "$base/Image" -OutFile "$tmp\Image" -UseBasicParsing

    $expected = ((Get-Content "$tmp\Image.sha256" -Raw).Trim() -split '\s+')[0].ToLower()
    $actual = (Get-FileHash "$tmp\Image" -Algorithm SHA256).Hash.ToLower()
    if ($expected -ne $actual) { throw "Checksum mismatch for kernel $KernelVersion (expected $expected, got $actual)" }
    Write-Host "    SHA-256 verified: $actual"
    "$tmp\Image"
}

if ($Revert) {
    Set-WslConfigKernel $null
    & wsl.exe --shutdown
    Write-Host '==> Reverted to the stock WSL kernel.'
    return
}

$image = Join-Path $KernelDir 'Image'
New-Item -ItemType Directory -Force $KernelDir | Out-Null

if (-not $SkipBuild -and -not $Build) {
    if (-not $Version) {
        $running = (& wsl.exe -d $Distro -- uname -r | Out-String).Trim()
        $Version = [regex]::Match($running, '^\d+(\.\d+)+').Value
        if (-not $Version) { throw "Could not read the WSL kernel version (uname -r: '$running')" }
    }
    $download = Get-PrebuiltKernel $Version
    if ($download) {
        # Stop WSL first so the kernel file in use can be replaced.
        & wsl.exe --shutdown
        Copy-Item $download $image -Force
        $SkipBuild = $true
    } else {
        Write-Warning "No prebuilt kernel for $Version in $ReleaseRepo; building locally instead."
        $Build = $true
    }
}

if ($Build) {
    Write-Host '==> Building kernel inside WSL (20-60 min the first time)'
    Invoke-RepoScript 'wsl/kernel/build-kernel.sh'
    & wsl.exe -d $Distro -- bash -c "cp ~/wsl-kernel-build/Image '$(ConvertTo-WslPath $image)'"
    if ($LASTEXITCODE -ne 0) { throw 'Copying the kernel Image failed' }
}
if (-not (Test-Path $image)) { throw "No kernel at $image" }

Set-WslConfigKernel $image
Write-Host '==> Restarting WSL to load the new kernel'
& wsl.exe --shutdown

$release = & wsl.exe -d $Distro -- uname -r
$binder = [int](& wsl.exe -d $Distro -- grep -c binder /proc/filesystems)
Write-Host "    kernel: $release   binder filesystems: $binder"
if ($binder -lt 1) { throw 'binder is not available after reboot; check .wslconfig' }
Write-Host '==> Kernel installed. Next: .\windows\android.ps1 setup'
