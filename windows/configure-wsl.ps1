<#
.SYNOPSIS
  Sets how much RAM / CPU / swap the WSL VM (and therefore Android) may use.
  Android runs in a container inside that VM, so these are its real limits.
  The values are caps, not reservations: unused RAM is returned to Windows.
.EXAMPLE
  .\windows\configure-wsl.ps1                         # defaults (4 GB, 4 cores)
  .\windows\configure-wsl.ps1 -MemoryGB 8 -Processors 6
#>
param(
    [int]$MemoryGB,
    [int]$Processors,
    [int]$SwapGB = 4,
    [switch]$NoRestart
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"

$totalGB = [math]::Floor((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
$cores = (Get-CimInstance Win32_Processor | Measure-Object NumberOfLogicalProcessors -Sum).Sum

# Android 13 idles at ~2-3 GB, so 4 GB / 4 cores runs a dev app smoothly
# while leaving Windows the rest for Metro, the IDE and the browser.
# Raise them only for heavy workloads (e.g. rebuilding the kernel).
if (-not $MemoryGB)   { $MemoryGB = [math]::Min(4, [math]::Floor($totalGB / 2)) }
if (-not $Processors) { $Processors = [math]::Min(4, [math]::Max(2, $cores - 2)) }

$settings = [ordered]@{
    memory     = "${MemoryGB}GB"
    processors = "$Processors"
    swap       = "${SwapGB}GB"
}

$lines = if (Test-Path $WslConfig) { @(Get-Content $WslConfig) } else { @('[wsl2]') }
if (-not (Test-Path "$WslConfig.bak") -and (Test-Path $WslConfig)) { Copy-Item $WslConfig "$WslConfig.bak" }
if (-not ($lines -match '^\s*\[wsl2\]\s*$')) { $lines = @('[wsl2]') + $lines }

foreach ($key in $settings.Keys) {
    $entry = "$key=$($settings[$key])"
    $idx = [Array]::FindIndex([string[]]$lines, [Predicate[string]]{ param($l) $l -match "^\s*$key\s*=" })
    if ($idx -ge 0) {
        $lines[$idx] = $entry
    } else {
        $at = [Array]::FindIndex([string[]]$lines, [Predicate[string]]{ param($l) $l -match '^\s*\[wsl2\]\s*$' })
        $lines = @($lines[0..$at]) + $entry + @(if ($at + 1 -lt $lines.Count) { $lines[($at + 1)..($lines.Count - 1)] })
    }
}

# Give freed memory back to Windows instead of holding it as page cache.
if (-not ($lines -match '^\s*autoMemoryReclaim\s*=')) {
    if (-not ($lines -match '^\s*\[experimental\]\s*$')) { $lines += '', '[experimental]' }
    $at = [Array]::FindIndex([string[]]$lines, [Predicate[string]]{ param($l) $l -match '^\s*\[experimental\]\s*$' })
    $lines = @($lines[0..$at]) + 'autoMemoryReclaim=dropCache' + @(if ($at + 1 -lt $lines.Count) { $lines[($at + 1)..($lines.Count - 1)] })
}

Set-Content -Path $WslConfig -Value $lines -Encoding ascii
Write-Host "==> WSL limits: $MemoryGB GB RAM, $Processors of $cores cores, $SwapGB GB swap (host has $totalGB GB)"

if (-not $NoRestart) {
    Write-Host '==> Restarting WSL to apply (Docker Desktop will restart its engine too)'
    & wsl.exe --shutdown
}
