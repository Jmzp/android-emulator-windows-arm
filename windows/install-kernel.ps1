<#
.SYNOPSIS
  Builds the binder-enabled WSL kernel inside the distro and points
  %USERPROFILE%\.wslconfig at it. Restarts WSL (Docker Desktop included).
.PARAMETER SkipBuild
  Reuse the Image already in %USERPROFILE%\wsl-kernel.
.PARAMETER Revert
  Remove the kernel= line and go back to Microsoft's stock kernel.
#>
param([switch]$SkipBuild, [switch]$Revert)
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

if ($Revert) {
    Set-WslConfigKernel $null
    & wsl.exe --shutdown
    Write-Host '==> Reverted to the stock WSL kernel.'
    return
}

$image = Join-Path $KernelDir 'Image'
if (-not $SkipBuild) {
    Write-Host '==> Building kernel inside WSL (20-60 min the first time)'
    Invoke-RepoScript 'wsl/kernel/build-kernel.sh'
    New-Item -ItemType Directory -Force $KernelDir | Out-Null
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
