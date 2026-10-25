<#
.SYNOPSIS
  Creates a desktop shortcut that starts Android and leaves adb connected,
  plus a "Send to" entry that installs APKs. The console window stays open
  showing the device serial and can be closed at any time. Closing the
  Android window shuts Android down.
.EXAMPLE
  .\windows\create-shortcut.ps1
  .\windows\create-shortcut.ps1 -Device pixel
  .\windows\create-shortcut.ps1 -Name 'Android' -Window 480x1040
#>
param(
    [string]$Name = 'Android Emulator',
    [ValidateSet('phone', 'small', 'pixel', 'tablet')][string]$Device,
    [string]$Window
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"

$icon = Join-Path $RepoRoot 'assets\android-emulator.ico'
if (-not (Test-Path $icon)) {
    # Draw a simple green rounded tile with a white phone outline.
    Add-Type -AssemblyName System.Drawing
    $size = 256
    $bmp = New-Object System.Drawing.Bitmap $size, $size
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear([System.Drawing.Color]::Transparent)

    function New-RoundRect([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
        $p = New-Object System.Drawing.Drawing2D.GraphicsPath
        $p.AddArc($x, $y, $r, $r, 180, 90)
        $p.AddArc($x + $w - $r, $y, $r, $r, 270, 90)
        $p.AddArc($x + $w - $r, $y + $h - $r, $r, $r, 0, 90)
        $p.AddArc($x, $y + $h - $r, $r, $r, 90, 90)
        $p.CloseFigure()
        $p
    }

    $g.FillPath((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(61, 220, 132))), (New-RoundRect 8 8 240 240 72))
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 14
    $g.DrawPath($pen, (New-RoundRect 78 40 100 176 36))
    $g.FillEllipse([System.Drawing.Brushes]::White, 116, 182, 24, 24)
    $g.Dispose()

    # Wrap the PNG in a single-image .ico container (Vista+ supports PNG icons).
    $png = New-Object System.IO.MemoryStream
    $bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    $bytes = $png.ToArray()
    New-Item -ItemType Directory -Force (Split-Path $icon) | Out-Null
    $fs = [System.IO.File]::Create($icon)
    $w = New-Object System.IO.BinaryWriter $fs
    $w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]1)    # header: icon, 1 image
    $w.Write([byte]0); $w.Write([byte]0); $w.Write([byte]0); $w.Write([byte]0)  # 256x256, no palette
    $w.Write([uint16]1); $w.Write([uint16]32)                        # planes, bpp
    $w.Write([uint32]$bytes.Length); $w.Write([uint32]22)            # size, offset
    $w.Write($bytes)
    $w.Close()
}

$shell = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
if (-not $shell) { $shell = (Get-Command powershell.exe).Source }

$script = Join-Path $PSScriptRoot 'android.ps1'
$arguments = "-NoExit -ExecutionPolicy Bypass -File `"$script`" start"
if ($Device) { $arguments += " -Device $Device" }
if ($Window) { $arguments += " -Window $Window" }

$wsh = New-Object -ComObject WScript.Shell
function New-Shortcut([string]$Path, [string]$Arguments, [string]$Description) {
    $lnk = $wsh.CreateShortcut($Path)
    $lnk.TargetPath = $shell
    $lnk.Arguments = $Arguments
    $lnk.WorkingDirectory = $RepoRoot
    $lnk.IconLocation = "$icon,0"
    $lnk.Description = $Description
    $lnk.Save()
    Write-Host "==> Shortcut created: $Path"
}

# There is no stop shortcut on purpose: closing the Android window shuts it down.
New-Shortcut (Join-Path ([Environment]::GetFolderPath('Desktop')) "$Name.lnk") $arguments `
    'Start Android (Waydroid on WSL) and connect adb'

# Right-click an .apk > Send to > Android Emulator. Explorer appends the
# selected files as extra arguments.
New-Shortcut (Join-Path ([Environment]::GetFolderPath('SendTo')) "$Name.lnk") `
    "-ExecutionPolicy Bypass -File `"$script`" install -Pause" 'Install APKs on the Android emulator'
