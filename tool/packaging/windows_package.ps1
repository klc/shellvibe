# Builds the ShellVibe Windows installer, and signs it when a certificate is
# available.
#
# Like the macOS packager this runs on every release build, signed or not, so
# the installer path is exercised long before the first build that has a
# certificate. An installer first produced on release day fails on release day.
#
# Environment:
#   WINDOWS_CERT_PATH      Path to a .pfx (signs when set together with the password)
#   WINDOWS_CERT_PASSWORD  Password for that .pfx
#   WINDOWS_TIMESTAMP_URL  RFC 3161 timestamp server (defaults to DigiCert's)
#
# Usage:
#   tool/packaging/windows_package.ps1 -Version 1.0.0 [-BuildDir ...] [-OutDir dist]

param(
    [Parameter(Mandatory = $true)][string]$Version,
    [string]$BuildDir = 'build/windows/x64/runner/Release',
    [string]$OutDir = 'dist'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $BuildDir)) { throw "No build output at $BuildDir" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$root = (Resolve-Path '.').Path
$build = (Resolve-Path $BuildDir).Path
$out = (Resolve-Path $OutDir).Path

$iscc = Get-Command 'iscc.exe' -ErrorAction SilentlyContinue
if (-not $iscc) {
    # Inno Setup ships on the GitHub Windows images but is not on PATH.
    $candidates = @(
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "${env:ProgramFiles}\Inno Setup 6\ISCC.exe"
    )
    $found = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $found) { throw 'Inno Setup (ISCC.exe) not found.' }
    $iscc = $found
} else {
    $iscc = $iscc.Source
}

$signtool = $null
if ($env:WINDOWS_CERT_PATH -and $env:WINDOWS_CERT_PASSWORD) {
    $kits = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin' -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending
    foreach ($kit in $kits) {
        $candidate = Join-Path $kit.FullName 'x64\signtool.exe'
        if (Test-Path $candidate) { $signtool = $candidate; break }
    }
    if (-not $signtool) { throw 'A certificate was supplied but signtool.exe was not found.' }
}

$timestamp = if ($env:WINDOWS_TIMESTAMP_URL) { $env:WINDOWS_TIMESTAMP_URL } else { 'http://timestamp.digicert.com' }

function Invoke-Sign([string]$Path) {
    if (-not $signtool) { return }
    Write-Host "==> Signing $Path"
    # SHA-256 throughout, and a countersigned timestamp so the signature stays
    # valid after the certificate itself expires.
    & $signtool sign /f $env:WINDOWS_CERT_PATH /p $env:WINDOWS_CERT_PASSWORD `
        /fd SHA256 /td SHA256 /tr $timestamp $Path
    if ($LASTEXITCODE -ne 0) { throw "signtool failed on $Path" }
}

if (-not $signtool) {
    Write-Host '==> No WINDOWS_CERT_PATH; building an unsigned installer.'
}

# The application first: an installer that carries an unsigned binary is signed
# packaging around unsigned software, and SmartScreen judges what gets executed.
Invoke-Sign (Join-Path $build 'shellvibe.exe')

Write-Host '==> Building installer'
& $iscc `
    "/DAppVersion=$Version" `
    "/DBuildDir=$build" `
    "/DOutputDir=$out" `
    "/DSourceRoot=$root" `
    'tool\packaging\windows_installer.iss'
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup failed.' }

$installer = Join-Path $out "ShellVibe-$Version-windows-x64-setup.exe"
if (-not (Test-Path $installer)) { throw "Expected $installer" }

Invoke-Sign $installer

if (-not $signtool) {
    $unsigned = Join-Path $out "ShellVibe-$Version-windows-x64-setup-unsigned.exe"
    Move-Item -Force $installer $unsigned
    $installer = $unsigned
}

Write-Host '==> Done:'
Get-Item $installer | Format-List Name, Length
