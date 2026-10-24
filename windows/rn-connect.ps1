<#
.SYNOPSIS
  Forwards Metro / Expo ports from Android to the Windows host so the app
  can reach the bundler at localhost, as it would on a regular emulator.
#>
param([int[]]$Ports = @(8081, 19000, 19001, 19002))
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"

$adb = Get-Adb
$serial = Get-AndroidSerial
foreach ($p in $Ports) {
    & $adb -s $serial reverse "tcp:$p" "tcp:$p" | Out-Null
}
& $adb -s $serial reverse --list
Write-Host "Set `$env:ANDROID_SERIAL = '$serial' so Expo / RN CLI pick this device."
