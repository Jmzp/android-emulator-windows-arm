<#
.SYNOPSIS
  Installs the Ubuntu arm64 WSL distro used to host Android and prepares it
  (non-root user with passwordless sudo, systemd enabled).
.EXAMPLE
  .\windows\setup-wsl.ps1
#>
param([string]$User = ($env:USERNAME.ToLower() -replace '[^a-z0-9_-]', ''))
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"

if (-not (Test-DistroInstalled)) {
    Write-Host "==> Installing $Distro"
    if ($Distro -eq $BaseDistro) { & wsl.exe --install -d $BaseDistro --no-launch }
    else { & wsl.exe --install -d $BaseDistro --name $Distro --no-launch }
    if ($LASTEXITCODE -ne 0) { throw "wsl --install failed (exit $LASTEXITCODE)" }
    if (-not (Test-DistroInstalled)) { throw "$Distro was not registered. Launch it once from the Start menu and re-run." }
}

Write-Host "==> Configuring $Distro (user '$User', systemd)"
$setup = @"
set -e
id -u $User >/dev/null 2>&1 || useradd -m -s /bin/bash -G sudo,adm,video,render $User
echo '$User ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-android-wsl
chmod 440 /etc/sudoers.d/90-android-wsl
cat > /etc/wsl.conf <<'EOF'
[boot]
systemd=true

[user]
default=$User
EOF
"@
# Pipe through tr so Windows line endings never reach bash.
$setup | & wsl.exe -d $Distro -u root -- bash -c "tr -d '\r' | bash"
if ($LASTEXITCODE -ne 0) { throw "Distro configuration failed (exit $LASTEXITCODE)" }

& wsl.exe --terminate $Distro | Out-Null
Write-Host "==> $Distro ready. Next: .\windows\install-kernel.ps1"
