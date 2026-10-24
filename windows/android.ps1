<#
.SYNOPSIS
  Day-to-day control of the Waydroid "emulator".
.EXAMPLE
  .\windows\android.ps1 start                  # phone-sized window (432x936)
  .\windows\android.ps1 start -Window 480x1040 # custom window size
  .\windows\android.ps1 start -Full            # use the whole WSLg window
  .\windows\android.ps1 stop
  .\windows\android.ps1 status
  .\windows\android.ps1 setup                  # one-time Waydroid install (-Gapps for Play Store)
#>
param(
    [Parameter(Position = 0)][ValidateSet('start', 'stop', 'status', 'setup')][string]$Command = 'start',
    [ValidatePattern('^\d+x\d+$')][string]$Window = '432x936',
    [switch]$Full,
    [switch]$Gapps
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"

# With systemd, WSL shuts the distro down once no wsl.exe client is attached,
# taking Android with it. A hidden `sleep infinity` keeps it alive.
$keepAlivePid = Join-Path $env:TEMP "android-wsl-keepalive-$Distro.pid"

function Start-KeepAlive {
    if (Test-Path $keepAlivePid) {
        $old = Get-Process -Id (Get-Content $keepAlivePid) -ErrorAction SilentlyContinue
        if ($old -and $old.ProcessName -eq 'wsl') { return }
    }
    # Created through WMI so it is not part of this console's process tree:
    # closing the console (or terminal tab) must not take Android down.
    $startup = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ ShowWindow = [uint16]0 }
    $r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
        CommandLine = "wsl.exe -d $Distro -- sleep infinity"
        ProcessStartupInformation = $startup
    }
    if ($r.ReturnValue -ne 0) { throw "Could not start the WSL keep-alive (Win32_Process.Create returned $($r.ReturnValue))" }
    Set-Content $keepAlivePid $r.ProcessId
}

function Stop-KeepAlive {
    if (-not (Test-Path $keepAlivePid)) { return }
    Get-Process -Id (Get-Content $keepAlivePid) -ErrorAction SilentlyContinue |
        Where-Object ProcessName -eq 'wsl' | Stop-Process -Force
    Remove-Item $keepAlivePid
}

switch ($Command) {
    'setup' {
        Invoke-RepoScript 'wsl/setup-waydroid.sh' @($(if ($Gapps) { 'GAPPS' } else { 'VANILLA' }))
    }
    'start' {
        Start-KeepAlive
        Invoke-RepoScript 'wsl/start-android.sh' @($(if ($Full) { 'full' } else { $Window }))

        $adb = Get-Adb
        $keyPub = Join-Path $env:USERPROFILE '.android\adbkey.pub'
        if (-not (Test-Path $keyPub)) { & $adb start-server | Out-Null }  # creates the key pair
        Invoke-RepoScript 'wsl/authorize-adb.sh' @(ConvertTo-WslPath $keyPub)

        $serial = Get-AndroidSerial
        & $adb disconnect $serial 2>$null | Out-Null
        & $adb connect $serial | Write-Host
        & $adb -s $serial wait-for-device
        Write-Host "==> Ready: $serial  $(& $adb -s $serial shell getprop ro.product.model) ($(& $adb -s $serial shell getprop ro.product.cpu.abi))"
        Write-Host "    Use it with: `$env:ANDROID_SERIAL = '$serial'"
        Write-Host '    React Native / Expo: .\windows\rn-connect.ps1, then npx expo run:android'
    }
    'stop' {
        $adb = Get-Adb
        & $adb disconnect (Get-AndroidSerial) 2>$null | Out-Null
        Invoke-RepoScript 'wsl/stop-android.sh'
        Stop-KeepAlive
    }
    'status' {
        & wsl.exe -d $Distro -- waydroid status
        & (Get-Adb) devices -l
    }
}
