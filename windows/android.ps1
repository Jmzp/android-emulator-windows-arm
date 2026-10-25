<#
.SYNOPSIS
  Day-to-day control of the Waydroid "emulator".
.EXAMPLE
  .\windows\android.ps1 start                  # phone-sized window (432x936)
  .\windows\android.ps1 start -Window 480x1040 # custom window size
  .\windows\android.ps1 start -Full            # use the whole WSLg window
  .\windows\android.ps1 start -NoReverse       # skip adb reverse for Metro / Expo
  .\windows\android.ps1 stop
  .\windows\android.ps1 status
  .\windows\android.ps1 doctor                 # diagnose the whole setup
  .\windows\android.ps1 setup                  # one-time Waydroid install (-Gapps for Play Store)
#>
param(
    [Parameter(Position = 0)][ValidateSet('start', 'stop', 'status', 'doctor', 'setup')][string]$Command = 'start',
    [ValidatePattern('^\d+x\d+$')][string]$Window = '432x936',
    [switch]$Full,
    [switch]$NoReverse,
    [switch]$Gapps
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"

# With systemd, WSL shuts the distro down once no wsl.exe client is attached,
# taking Android with it. A hidden wsl.exe running keep-alive.sh holds it up
# for as long as the Android window is open, then exits so WSL can free RAM.
$keepAlivePid = Join-Path $env:TEMP "android-wsl-keepalive-$Distro.pid"

function Start-KeepAlive([string]$Unit) {
    if (Test-Path $keepAlivePid) {
        $old = Get-Process -Id (Get-Content $keepAlivePid) -ErrorAction SilentlyContinue
        if ($old -and $old.ProcessName -eq 'wsl') { return }
    }
    # Created through WMI so it is not part of this console's process tree:
    # closing the console (or terminal tab) must not take Android down.
    $script = ConvertTo-WslPath (Join-Path $RepoRoot 'wsl\keep-alive.sh')
    $startup = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ ShowWindow = [uint16]0 }
    $r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
        CommandLine = "wsl.exe -d $Distro --cd ~ -- bash `"$script`" $Unit"
        ProcessStartupInformation = $startup
    }
    if ($r.ReturnValue -ne 0) { throw "Could not start the WSL keep-alive (Win32_Process.Create returned $($r.ReturnValue))" }
    Set-Content $keepAlivePid $r.ProcessId
}

# keep-alive.sh exits by itself once the window unit stops. Killing wsl.exe
# instead can leave the WSL service hung, so that is only a last resort.
function Stop-KeepAlive {
    if (-not (Test-Path $keepAlivePid)) { return }
    $p = Get-Process -Id (Get-Content $keepAlivePid) -ErrorAction SilentlyContinue | Where-Object ProcessName -eq 'wsl'
    if ($p -and -not $p.WaitForExit(20000)) { $p | Stop-Process -Force }
    Remove-Item $keepAlivePid
}

# Older versions connected by WSL IP; that entry would list the device twice.
function Remove-LegacyConnection([string]$Adb) {
    $ip = Get-WslIp
    if ($ip) { & $Adb disconnect "${ip}:$AdbPort" 2>$null | Out-Null }
}

function Wait-Emulator([string]$Adb, [string]$Serial, [int]$Seconds = 60) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        if ((& $Adb -s $Serial get-state 2>$null) -eq 'device') { return }
        Start-Sleep 1
    }
    throw "$Serial did not show up in 'adb devices'. Run .\windows\android.ps1 doctor"
}

switch ($Command) {
    'setup' {
        Invoke-RepoScript 'wsl/setup-waydroid.sh' @($(if ($Gapps) { 'GAPPS' } else { 'VANILLA' }))
    }
    'start' {
        # Track the phone window (Weston). With -Full there is no Weston, and
        # `show-full-ui` exits right away, so track the session instead.
        Start-KeepAlive $(if ($Full) { 'waydroid-session' } else { 'waydroid-weston' })
        Invoke-RepoScript 'wsl/start-android.sh' @($(if ($Full) { 'full' } else { $Window }))

        $adb = Get-Adb
        $keyPub = Join-Path $env:USERPROFILE '.android\adbkey.pub'
        if (-not (Test-Path $keyPub)) { & $adb start-server | Out-Null }  # creates the key pair
        Invoke-RepoScript 'wsl/authorize-adb.sh' @(ConvertTo-WslPath $keyPub)

        $serial = Get-AndroidSerial
        Remove-LegacyConnection $adb
        Wait-Emulator $adb $serial
        if (-not $NoReverse) { Set-AdbReverse $adb $serial }

        $model = & $adb -s $serial shell getprop ro.product.model
        $abi = & $adb -s $serial shell getprop ro.product.cpu.abi
        Write-Host "==> Ready: $serial  $model ($abi)"
        if (-not $NoReverse) { Write-Host "    adb reverse: $($DefaultReversePorts -join ', ') (Metro / Expo)" }
        Write-Host '    Try: npx expo start --android   |   npx react-native run-android   |   flutter run'
    }
    'stop' {
        Invoke-RepoScript 'wsl/stop-android.sh'
        Stop-KeepAlive
    }
    'status' {
        & wsl.exe -d $Distro -- waydroid status
        & (Get-Adb) devices -l
    }
    'doctor' {
        & (Join-Path $PSScriptRoot 'doctor.ps1')
    }
}
