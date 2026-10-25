<#
.SYNOPSIS
  Forwards Metro / Expo ports from Android to the Windows host so the app
  can reach the bundler at localhost, as it would on a regular emulator.
  `android.ps1 start` already does this; use it again after Android restarts
  or for extra ports.
.EXAMPLE
  .\windows\rn-connect.ps1
  .\windows\rn-connect.ps1 -Ports 8081, 3000
#>
param([int[]]$Ports = @())
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"

if (-not $Ports) { $Ports = $DefaultReversePorts }
$adb = Get-Adb
$serial = Get-AndroidSerial
Set-AdbReverse $adb $serial $Ports
& $adb -s $serial reverse --list
