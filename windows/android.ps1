<#
.SYNOPSIS
  Day-to-day control of the Waydroid "emulator".
.EXAMPLE
  .\windows\android.ps1 start                  # phone-sized window (432x936)
  .\windows\android.ps1 start -Device tablet   # profiles: phone, small, pixel, tablet
  .\windows\android.ps1 start -Window 480x1040 -Density 200
  .\windows\android.ps1 start -Full            # use the whole WSLg window
  .\windows\android.ps1 start -NoReverse       # skip adb reverse for Metro / Expo
  .\windows\android.ps1 rotate                 # swap portrait / landscape (restarts Android)
  .\windows\android.ps1 stop
  .\windows\android.ps1 install app.apk        # starts Android first if needed
  .\windows\android.ps1 screenshot [file.png]  # default: Pictures\Android Emulator
  .\windows\android.ps1 record [file.mp4]      # Enter stops; -Seconds caps it (max 180)
  .\windows\android.ps1 snapshot list | save NAME | restore NAME | delete NAME
  .\windows\android.ps1 wipe                   # factory reset of Android's data
  .\windows\android.ps1 status
  .\windows\android.ps1 doctor                 # diagnose the whole setup
  .\windows\android.ps1 setup                  # one-time Waydroid install
  .\windows\android.ps1 setup -Gapps           # switch to Play Store / Play services (-Vanilla to go back)
  .\windows\android.ps1 register               # Android ID for Google's device registration (GAPPS)
#>
param(
    [Parameter(Position = 0)]
    [ValidateSet('start', 'stop', 'rotate', 'status', 'doctor', 'setup', 'install', 'screenshot', 'record', 'snapshot', 'wipe', 'register')]
    [string]$Command = 'start',
    [Parameter(Position = 1, ValueFromRemainingArguments)][string[]]$Arguments = @(),
    [ValidateSet('phone', 'small', 'pixel', 'tablet')][string]$Device,
    [ValidatePattern('^\d+x\d+$')][string]$Window,
    [ValidateRange(80, 640)][int]$Density,
    [switch]$Full,
    [switch]$NoReverse,
    [switch]$Gapps,
    [switch]$Vanilla,
    [ValidateRange(1, 180)][int]$Seconds = 180,
    [switch]$Force,
    [switch]$Pause
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"

# With systemd, WSL shuts the distro down once no wsl.exe client is attached,
# taking Android with it. A hidden wsl.exe running keep-alive.sh holds it up
# for as long as the Android window is open, then exits so WSL can free RAM.
$keepAlivePid = Join-Path $env:TEMP "android-wsl-keepalive-$Distro.pid"
$lastStart = Join-Path $StateDir 'last-start.json'

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

function Test-AndroidRunning {
    [bool]((& wsl.exe -d $Distro -- waydroid status 2>$null) -match 'Session:\s+RUNNING')
}

# Start options, from (in order) -Window/-Density, -Device, or the default phone.
function Resolve-StartOptions {
    if ($Full) { return @{ Window = 'full'; Density = $(if ($Density) { $Density }); Device = 'full' } }
    $o = @{ Window = $DeviceProfiles.phone.Window; Density = $DeviceProfiles.phone.Density; Device = 'phone' }
    if ($Device) {
        $p = $DeviceProfiles[$Device]
        $o = @{ Window = $p.Window; Density = $p.Density; Device = $Device }
    }
    if ($Window) { $o.Window = $Window; $o.Device = 'custom' }
    if ($Density) { $o.Density = $Density }
    $o
}

function Get-LastStart {
    if (Test-Path $lastStart) {
        $j = Get-Content $lastStart -Raw | ConvertFrom-Json
        return @{ Window = $j.Window; Density = $j.Density; Device = $j.Device }
    }
    @{ Window = $DeviceProfiles.phone.Window; Density = $DeviceProfiles.phone.Density; Device = 'phone' }
}

function Start-Android([hashtable]$Options) {
    $isFull = $Options.Window -eq 'full'
    # Track the phone window (Weston). With -Full there is no Weston, and
    # `show-full-ui` exits right away, so track the session instead.
    Start-KeepAlive $(if ($isFull) { 'waydroid-session' } else { 'waydroid-weston' })
    Invoke-RepoScript 'wsl/start-android.sh' @($Options.Window)
    New-Item -ItemType Directory -Force $StateDir | Out-Null
    $Options | ConvertTo-Json | Set-Content $lastStart

    $adb = Get-Adb
    $keyPub = Join-Path $env:USERPROFILE '.android\adbkey.pub'
    if (-not (Test-Path $keyPub)) { & $adb start-server | Out-Null }  # creates the key pair
    Invoke-RepoScript 'wsl/authorize-adb.sh' @(ConvertTo-WslPath $keyPub)

    $serial = Get-AndroidSerial
    Remove-LegacyConnection $adb
    Register-Emulator $adb
    Wait-Emulator $adb $serial
    # wm density persists across reboots, so always set it (or clear it).
    if ($Options.Density) { & $adb -s $serial shell wm density $Options.Density | Out-Null }
    else { & $adb -s $serial shell wm density reset | Out-Null }
    if (-not $NoReverse) { Set-AdbReverse $adb $serial }

    $model = & $adb -s $serial shell getprop ro.product.model
    $abi = & $adb -s $serial shell getprop ro.product.cpu.abi
    $dpi = (& $adb -s $serial shell wm density | Select-Object -Last 1) -replace '\D'
    Write-Host "==> Ready: $serial  $model ($abi)  $($Options.Device) $($Options.Window) @ ${dpi}dpi"
    if (-not $NoReverse) { Write-Host "    adb reverse: $($DefaultReversePorts -join ', ') (Metro / Expo)" }
    Write-Host '    Try: npx expo start --android   |   npx react-native run-android   |   flutter run'
}

function Stop-Android {
    Invoke-RepoScript 'wsl/stop-android.sh'
    Stop-KeepAlive
}

# Returns the serial of a running, adb-connected Android, starting it if needed.
function Initialize-Android {
    $adb = Get-Adb
    $serial = Get-AndroidSerial
    if ((& $adb -s $serial get-state 2>$null) -ne 'device') {
        if (Test-AndroidRunning) { Register-Emulator $adb; Wait-Emulator $adb $serial 15 }
        else {
            Write-Host '==> Android is not running; starting it'
            Start-Android (Get-LastStart) | Out-Host  # keep its output out of the return value
        }
    }
    $serial
}

# Runs a snapshot.sh action with Android stopped, restarting it afterwards
# if it was running.
function Invoke-WithAndroidStopped([string[]]$SnapshotArgs) {
    $wasRunning = Test-AndroidRunning
    if ($wasRunning) { Write-Host '==> Stopping Android'; Stop-Android }
    Invoke-RepoScript 'wsl/snapshot.sh' $SnapshotArgs
    if ($wasRunning) { Start-Android (Get-LastStart) }
}

function Confirm-Action([string]$Message) {
    if ($Force) { return }
    $answer = Read-Host "$Message [y/N]"
    if ($answer -notmatch '^(y|yes|s|si)$') { Write-Host 'Cancelled.'; exit 1 }
}

function Get-OutputPath([string]$Folder, [string]$Prefix, [string]$Extension) {
    if ($Arguments.Count -gt 0) { return [IO.Path]::GetFullPath($Arguments[0]) }
    $dir = Join-Path ([Environment]::GetFolderPath($Folder)) 'Android Emulator'
    New-Item -ItemType Directory -Force $dir | Out-Null
    Join-Path $dir "$Prefix-$(Get-Date -Format 'yyyyMMdd-HHmmss').$Extension"
}

switch ($Command) {
    'setup' {
        if ($Gapps -and $Vanilla) { throw 'Choose -Gapps or -Vanilla, not both' }
        # KEEP leaves the installed image type alone (VANILLA on a new install).
        $type = if ($Gapps) { 'GAPPS' } elseif ($Vanilla) { 'VANILLA' } else { 'KEEP' }
        # Switching images needs Android stopped; bring it back afterwards.
        $wasRunning = $type -ne 'KEEP' -and (Test-AndroidRunning)
        if ($wasRunning) { Write-Host '==> Stopping Android'; Stop-Android }
        Invoke-RepoScript 'wsl/setup-waydroid.sh' @($type, $ReleaseRepo)
        if ($wasRunning) { Start-Android (Get-LastStart) }
        if ($Gapps) {
            Write-Host '==> Google Play is installed. Google blocks uncertified devices until you register them:'
            Write-Host '    start Android, wait a minute, then run .\windows\android.ps1 register'
        }
    }
    'start' {
        $o = Resolve-StartOptions
        # A running window keeps its size, so a different size means a restart.
        if ((Get-LastStart).Window -ne $o.Window -and (Test-AndroidRunning)) {
            Write-Host "==> Switching to $($o.Window) (Android restarts)"
            Stop-Android
        }
        Start-Android $o
    }
    'stop' {
        Stop-Android
    }
    'rotate' {
        $o = Get-LastStart
        if ($o.Window -eq 'full') { throw 'rotate needs a window size; it does not apply to -Full' }
        $w, $h = $o.Window -split 'x'
        $o.Window = "${h}x${w}"
        # The nested window can't change size on the fly and Android's display
        # can't follow a new compositor, so rotating means a quick restart.
        Write-Host "==> Rotating to $($o.Window) (Android restarts, ~30 s)"
        if (Test-AndroidRunning) { Stop-Android }
        Start-Android $o
    }
    'status' {
        & wsl.exe -d $Distro -- waydroid status
        & (Get-Adb) devices -l
        $o = Get-LastStart
        Write-Host "Last start: $($o.Device) $($o.Window) @ $($o.Density)dpi"
    }
    'doctor' {
        & (Join-Path $PSScriptRoot 'doctor.ps1')
    }
    'install' {
        try {
            if ($Arguments.Count -eq 0) { throw 'Usage: android.ps1 install <file.apk> [more.apk ...]' }
            $serial = Initialize-Android
            $adb = Get-Adb
            foreach ($apk in $Arguments) {
                Write-Host "==> Installing $(Split-Path $apk -Leaf)"
                & $adb -s $serial install -r $apk
                if ($LASTEXITCODE -ne 0) { throw "adb install failed for $apk" }
            }
        } catch {
            Write-Host $_ -ForegroundColor Red
            if ($Pause) { Read-Host 'Press Enter to close' | Out-Null }
            exit 1
        }
        if ($Pause) { Start-Sleep 3 }
    }
    'screenshot' {
        $serial = Initialize-Android
        $adb = Get-Adb
        $out = Get-OutputPath 'MyPictures' 'screenshot' 'png'
        $tmp = '/data/local/tmp/android-wsl-screenshot.png'
        & $adb -s $serial shell screencap -p $tmp
        & $adb -s $serial pull $tmp $out 2>&1 | Out-Null
        & $adb -s $serial shell rm $tmp
        Write-Host "==> Saved $out"
    }
    'record' {
        $null = Initialize-Android
        $out = Get-OutputPath 'MyVideos' 'recording' 'mp4'
        # Recorded from WSL (see record.py); the stop file ends it cleanly.
        $stopFile = '/tmp/android-wsl-record.stop'
        $script = ConvertTo-WslPath (Join-Path $RepoRoot 'wsl\record.py')
        $rec = Start-Process wsl.exe -ArgumentList '-d', $Distro, '--', 'python3', "`"$script`"", "`"$(ConvertTo-WslPath $out)`"", $Seconds, $stopFile -NoNewWindow -PassThru
        if ([Console]::IsInputRedirected) {
            Write-Host "==> Recording for $Seconds s"
        } else {
            Write-Host "==> Recording... press Enter to stop (max $Seconds s)"
            while (-not $rec.HasExited) {
                if ([Console]::KeyAvailable -and [Console]::ReadKey($true).Key -eq 'Enter') {
                    & wsl.exe -d $Distro -- touch $stopFile
                    break
                }
                Start-Sleep -Milliseconds 200
            }
        }
        $rec.WaitForExit()
        if ($rec.ExitCode -ne 0 -or -not (Test-Path $out)) { throw "Recording failed (exit $($rec.ExitCode))" }
        Write-Host "==> Saved $out"
    }
    'snapshot' {
        $action = if ($Arguments.Count -gt 0) { $Arguments[0] } else { 'list' }
        $name = if ($Arguments.Count -gt 1) { $Arguments[1] } else { '' }
        switch ($action) {
            'list' { Invoke-RepoScript 'wsl/snapshot.sh' @('list') }
            { $_ -in 'save', 'delete' } {
                if (-not $name) { throw "Usage: android.ps1 snapshot $action NAME" }
                if ($action -eq 'save') { Invoke-WithAndroidStopped @('save', $name) }
                else { Invoke-RepoScript 'wsl/snapshot.sh' @('delete', $name) }
            }
            'restore' {
                if (-not $name) { throw 'Usage: android.ps1 snapshot restore NAME' }
                Confirm-Action "Replace Android's current data with snapshot '$name'?"
                Invoke-WithAndroidStopped @('restore', $name)
            }
            default { throw 'Usage: android.ps1 snapshot list | save NAME | restore NAME | delete NAME' }
        }
    }
    'register' {
        $null = Initialize-Android
        $script = ConvertTo-WslPath (Join-Path $RepoRoot 'wsl\gsf-id.sh')
        $id = & wsl.exe -d $Distro --cd '~' -- bash $script
        if ($LASTEXITCODE -eq 3) { throw 'Play services has no Android ID yet. Wait a minute after boot (or open the Play Store once), then run this again.' }
        if ($LASTEXITCODE -ne 0) { throw 'Could not read the Android ID (see above).' }
        Set-Clipboard $id
        Write-Host "==> Android ID: $id (copied to the clipboard)"
        Write-Host '    1. On the page that opens, sign in, paste the ID and click Register.'
        Write-Host '    2. Wait a few minutes, then restart Android (close its window and reopen it).'
        Start-Process 'https://www.google.com/android/uncertified'
    }
    'wipe' {
        Confirm-Action 'Erase all apps and data in Android (like a factory reset)?'
        Invoke-WithAndroidStopped @('wipe')
    }
}
