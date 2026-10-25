<#
.SYNOPSIS
  One-step install of the Android emulator for Windows on ARM.
  Checks the machine first, then runs every setup step in order. Safe to run
  again: steps that are already done are skipped.
.EXAMPLE
  .\install.ps1                 # full install + desktop shortcut
  .\install.ps1 -Gapps          # with Play Store
  .\install.ps1 -Start          # start Android when done
.PARAMETER SkipLimits
  Leave the WSL RAM/CPU limits in .wslconfig untouched.
.PARAMETER NoShortcut
  Don't create the desktop shortcut.
#>
param([switch]$Gapps, [switch]$Start, [switch]$SkipLimits, [switch]$NoShortcut)
$ErrorActionPreference = 'Stop'
$win = Join-Path $PSScriptRoot 'windows'
. "$win\common.ps1"

function Write-Step([string]$Text) { Write-Host ''; Write-Host $Text -ForegroundColor Cyan }

Write-Step '==> Checking this machine'
$problems = @()
if ($env:PROCESSOR_ARCHITECTURE -ne 'ARM64') { $problems += "This is not an ARM64 machine ($env:PROCESSOR_ARCHITECTURE)." }
if ([Environment]::OSVersion.Version.Build -lt 22000) { $problems += 'Windows 11 is required.' }
& wsl.exe --version *> $null
if ($LASTEXITCODE -ne 0) { $problems += 'WSL is not installed. Run "wsl --install --no-distribution" as administrator, reboot, then run this again.' }
try { $adb = Get-Adb } catch { $problems += 'adb.exe was not found. Install it with "winget install Google.PlatformTools" (or Android Studio), then run this again.' }
$freeGB = [math]::Floor((Get-PSDrive ($env:SystemDrive.TrimEnd(':'))).Free / 1GB)
if ($freeGB -lt 10) { $problems += "Only $freeGB GB free on $env:SystemDrive; about 10 GB are needed." }
if ($problems) {
    $problems | ForEach-Object { Write-Host "  [FAIL] $_" -ForegroundColor Red }
    exit 1
}
Write-Host "  ARM64, Windows build $([Environment]::OSVersion.Version.Build), WSL, adb and $freeGB GB free: OK" -ForegroundColor Green

Write-Step '==> [1/5] Ubuntu distro for WSL'
& "$win\setup-wsl.ps1"

Write-Step '==> [2/5] WSL resource limits'
if ($SkipLimits) { Write-Host '  Skipped (-SkipLimits).' } else { & "$win\configure-wsl.ps1" }

Write-Step '==> [3/5] WSL kernel with binder'
& "$win\install-kernel.ps1"

Write-Step '==> [4/5] Waydroid and Android'
& "$win\android.ps1" setup -Gapps:$Gapps

Write-Step '==> [5/5] Desktop shortcut'
if ($NoShortcut) { Write-Host '  Skipped (-NoShortcut).' } else { & "$win\create-shortcut.ps1" }

Write-Step '==> Installed'
Write-Host '  Open:   double-click "Android Emulator" on the desktop, or .\windows\android.ps1 start'
Write-Host '  Close:  click the X on the Android window'
Write-Host '  Check:  .\windows\android.ps1 doctor'
if ($Start) { & "$win\android.ps1" start }
