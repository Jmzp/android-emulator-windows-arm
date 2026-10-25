<#
.SYNOPSIS
  Diagnoses the whole stack (Windows, WSL, kernel, Waydroid, adb) and prints
  a fix for every problem found. Exits with 1 if anything failed.
.EXAMPLE
  .\windows\android.ps1 doctor
#>
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"

$script:failures = 0
$script:warnings = 0
function Write-Check([string]$Status, [string]$What, [string]$Fix) {
    $color = @{ PASS = 'Green'; WARN = 'Yellow'; FAIL = 'Red'; INFO = 'Cyan' }[$Status]
    Write-Host ("  [{0}] {1}" -f $Status, $What) -ForegroundColor $color
    if ($Fix) { Write-Host "         -> $Fix" -ForegroundColor DarkGray }
    if ($Status -eq 'FAIL') { $script:failures++ }
    if ($Status -eq 'WARN') { $script:warnings++ }
}

# Runs wsl.exe with a timeout so a hung WSL service is reported, not waited on.
function Invoke-WslTimeout([string[]]$Arguments, [int]$Seconds = 30) {
    $job = Start-Job { param($a) $env:WSL_UTF8 = '1'; & wsl.exe @a 2>&1 } -ArgumentList (, $Arguments)
    if (Wait-Job $job -Timeout $Seconds) { $out = Receive-Job $job; Remove-Job $job; return , $out }
    Stop-Job $job; Remove-Job $job -Force
    return $null
}

Write-Host '==> Windows'
if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { Write-Check PASS 'Windows on ARM64' }
else { Write-Check FAIL "Not an ARM64 machine ($env:PROCESSOR_ARCHITECTURE)" 'This project targets Windows on ARM' }

$build = [Environment]::OSVersion.Version.Build
if ($build -ge 22000) { Write-Check PASS "Windows 11 (build $build)" }
else { Write-Check FAIL "Windows build $build is older than Windows 11" 'Update to Windows 11' }

$wslOut = & wsl.exe --version 2>$null
$wslCode = $LASTEXITCODE
$wslVersion = "$($wslOut | Select-Object -First 1)" -replace '[^\d\.]', ''
if ($wslCode -eq 0 -and $wslVersion) { Write-Check PASS "WSL $wslVersion" }
else { Write-Check FAIL 'WSL is not installed (or too old for wsl --version)' 'wsl --install --no-distribution, then reboot' }

try {
    $adb = Get-Adb
    Write-Check PASS "adb found ($adb)"
    if (Test-Path (Join-Path $env:USERPROFILE '.android\adbkey.pub')) { Write-Check PASS 'adb key exists' }
    else { Write-Check INFO 'No adb key yet; it is created on the first android.ps1 start' }
} catch {
    $adb = $null
    Write-Check FAIL 'adb.exe not found' 'Install Android SDK platform-tools (Android Studio, or winget install Google.PlatformTools)'
}

$kernelLine = if (Test-Path $WslConfig) { Get-Content $WslConfig | Where-Object { $_ -match '^\s*kernel\s*=' } | Select-Object -First 1 }
if ($kernelLine) {
    $kernelPath = ($kernelLine -split '=', 2)[1].Trim() -replace '\\\\', '\'
    if (Test-Path $kernelPath) { Write-Check PASS "Custom kernel configured ($kernelPath)" }
    else { Write-Check FAIL "kernel= points to a missing file ($kernelPath)" 'Run .\windows\install-kernel.ps1' }
} else {
    Write-Check FAIL 'No custom kernel in .wslconfig' 'Run .\windows\install-kernel.ps1'
}

Write-Host "==> WSL ($Distro)"
$alive = Invoke-WslTimeout @('-d', $Distro, '--', 'echo', 'alive')
if ($null -eq $alive) {
    Write-Check FAIL 'WSL does not respond (service hung)' 'wsl --shutdown --force, then android.ps1 start'
} elseif (($alive -join '') -notmatch 'alive') {
    Write-Check FAIL "Distro $Distro is not available" 'Run .\windows\setup-wsl.ps1'
} else {
    Write-Check PASS 'WSL responds'
    $doctor = ConvertTo-WslPath (Join-Path $RepoRoot 'wsl\doctor.sh')
    $lines = Invoke-WslTimeout @('-d', $Distro, '--cd', '~', '--', 'env', "ADB_PORT=$AdbPort", 'bash', $doctor) 60
    if ($null -eq $lines) { Write-Check FAIL 'Linux checks timed out' 'wsl --shutdown --force, then android.ps1 start' }
    foreach ($line in $lines) {
        $parts = "$line".Trim() -split '\|', 3
        if ($parts[0] -in 'PASS', 'WARN', 'FAIL', 'INFO') { Write-Check $parts[0] $parts[1] $(if ($parts.Count -gt 2) { $parts[2] }) }
    }
    $running = $lines -match '^PASS\|Android session running'

    if ($running -and $adb) {
        Write-Host '==> adb (Windows)'
        $serial = Get-AndroidSerial
        if (Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort $AdbPort -State Listen -ErrorAction SilentlyContinue) {
            Write-Check PASS "127.0.0.1:$AdbPort forwarded from WSL"
        } else {
            Write-Check FAIL "127.0.0.1:$AdbPort is not forwarded to Windows" 'Check localhostForwarding in .wslconfig (must not be false), then android.ps1 stop / start'
        }
        if ((& $adb -s $serial get-state 2>$null) -eq 'device') {
            Write-Check PASS "$serial connected"
            $reverse = & $adb -s $serial reverse --list 2>$null
            if ($reverse -match 'tcp:8081') { Write-Check PASS 'adb reverse for Metro (8081) set' }
            else { Write-Check WARN 'adb reverse for Metro (8081) missing' 'Run .\windows\rn-connect.ps1' }
        } else {
            $state = (& $adb devices | Select-String $serial) -replace '\s+', ' '
            Write-Check FAIL "$serial not ready ($(if ($state) { $state } else { 'not listed' }))" 'Run .\windows\android.ps1 stop, then start'
        }
    }
}

Write-Host ''
if ($script:failures) { Write-Host "$($script:failures) problem(s), $($script:warnings) warning(s)." -ForegroundColor Red; exit 1 }
elseif ($script:warnings) { Write-Host "No problems, $($script:warnings) warning(s)." -ForegroundColor Yellow }
else { Write-Host 'Everything looks good.' -ForegroundColor Green }
