# Builds the MSIX package ShellVibe is submitted to the Microsoft Store with.
#
# The package is left unsigned: the Store signs what it distributes, which is
# what makes this the one Windows channel that is signed without a certificate
# of our own. The same file cannot be installed outside the Store, so it is not
# a release asset; the GitHub release keeps the installer and the portable zip.
#
# Like the installer, this runs on every release build, so packaging breaks
# here and not on the day of the first Store submission. Without the Partner
# Center values it uses placeholders, which build a valid package that the
# Store would refuse.
#
# Environment (Partner Center > Product management > Product identity):
#   MSIX_IDENTITY_NAME              Package/Identity/Name
#   MSIX_PUBLISHER                  Package/Identity/Publisher, "CN=..."
#   MSIX_PUBLISHER_DISPLAY_NAME     Package/Properties/PublisherDisplayName
#
# Usage:
#   tool/packaging/windows_msix.ps1 -Version 1.0.0 [-BuildDir ...] [-OutDir dist-store] [-KeepStage]
#
# -KeepStage leaves the unpacked layout in place and prints its path. In a
# Windows VM with Developer Mode on, it installs without a signature:
#   Add-AppxPackage -Register <stage>\AppxManifest.xml

param(
    [Parameter(Mandatory = $true)][string]$Version,
    [string]$BuildDir = 'build/windows/x64/runner/Release',
    [string]$OutDir = 'dist-store',
    [switch]$KeepStage
)

$ErrorActionPreference = 'Stop'

if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    throw "Version must be major.minor.patch, got '$Version'."
}
# The Store reserves the fourth field and requires it to be 0.
$packageVersion = "$Version.0"

if (-not (Test-Path $BuildDir)) { throw "No build output at $BuildDir" }
foreach ($exe in 'shellvibe.exe', 'shellvibe-mcp.exe') {
    if (-not (Test-Path (Join-Path $BuildDir $exe))) {
        throw "$exe is missing from $BuildDir; the manifest declares it."
    }
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$root = (Resolve-Path '.').Path
$build = (Resolve-Path $BuildDir).Path
$out = (Resolve-Path $OutDir).Path
$template = Join-Path $root 'tool\packaging\windows_msix'

$identityName = if ($env:MSIX_IDENTITY_NAME) { $env:MSIX_IDENTITY_NAME } else { 'ShellVibe.Unregistered' }
$publisher = if ($env:MSIX_PUBLISHER) { $env:MSIX_PUBLISHER } else { 'CN=ShellVibe Unregistered' }
$publisherDisplayName = if ($env:MSIX_PUBLISHER_DISPLAY_NAME) { $env:MSIX_PUBLISHER_DISPLAY_NAME } else { 'ShellVibe' }
if (-not $env:MSIX_IDENTITY_NAME) {
    Write-Host '==> No MSIX_IDENTITY_NAME; packaging with placeholder identity values.'
}

$kitTool = @{}
$kits = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin' -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^10\.' } |
    Sort-Object { [version]$_.Name } -Descending
foreach ($name in 'makeappx.exe', 'makepri.exe') {
    foreach ($kit in $kits) {
        $candidate = Join-Path $kit.FullName "x64\$name"
        if (Test-Path $candidate) { $kitTool[$name] = $candidate; break }
    }
    if (-not $kitTool[$name]) { throw "$name not found in the Windows SDK." }
}

$stage = Join-Path ([IO.Path]::GetTempPath()) "shellvibe-msix-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $stage | Out-Null

Write-Host "==> Staging into $stage"
Copy-Item -Path (Join-Path $build '*') -Destination $stage -Recurse
Copy-Item -Path (Join-Path $template 'Assets') -Destination $stage -Recurse

function ConvertTo-XmlText([string]$Value) {
    return [Security.SecurityElement]::Escape($Value)
}

$manifest = Get-Content -Raw (Join-Path $template 'AppxManifest.xml')
$manifest = $manifest.
    Replace('@IDENTITY_NAME@', (ConvertTo-XmlText $identityName)).
    Replace('@PUBLISHER@', (ConvertTo-XmlText $publisher)).
    Replace('@PUBLISHER_DISPLAY_NAME@', (ConvertTo-XmlText $publisherDisplayName)).
    Replace('@VERSION@', $packageVersion)
if ($manifest -match '@[A-Z_]+@') { throw "Unfilled manifest value $($Matches[0])." }
# Parsed once here so a malformed manifest fails with a line number instead of
# a makeappx error code.
[xml]$manifest | Out-Null
[IO.File]::WriteAllText((Join-Path $stage 'AppxManifest.xml'), $manifest, (New-Object Text.UTF8Encoding $false))

Write-Host '==> Indexing resources'
# resources.pri is what lets Windows pick the scale and target-size variants
# of each logo the manifest names once. Only the logos are indexed: makepri
# reads folder and file name segments as qualifiers, and the Flutter assets
# are not named with that in mind. Paths in the index are relative, so one
# built beside a copy of Assets\ resolves the same inside the package.
$priRoot = Join-Path ([IO.Path]::GetTempPath()) "shellvibe-pri-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $priRoot | Out-Null
Copy-Item -Path (Join-Path $template 'Assets') -Destination $priRoot -Recurse
Copy-Item -Path (Join-Path $stage 'AppxManifest.xml') -Destination $priRoot
$priConfig = Join-Path $priRoot 'priconfig.xml'
& $kitTool['makepri.exe'] createconfig /cf $priConfig /dq en-US /o | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'makepri createconfig failed.' }
# The default config splits scale variants into resources.scale-200.pri and
# the like, which only resource packages in a bundle use. One package keeps
# every logo in resources.pri, so the split is turned off.
[xml]$priXml = Get-Content -Raw $priConfig
foreach ($node in @($priXml.SelectNodes('//packaging'))) {
    [void]$node.ParentNode.RemoveChild($node)
}
$priXml.Save($priConfig)
& $kitTool['makepri.exe'] new /pr $priRoot /cf $priConfig /mn (Join-Path $priRoot 'AppxManifest.xml') /of (Join-Path $stage 'resources.pri') /o | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'makepri new failed.' }
Remove-Item -Recurse -Force $priRoot

$msix = Join-Path $out "ShellVibe-$Version-windows-x64.msix"
Write-Host '==> Packing'
& $kitTool['makeappx.exe'] pack /d $stage /p $msix /o /h SHA256 | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'makeappx pack failed.' }

if ($KeepStage) {
    Write-Host "==> Layout kept at $stage"
} else {
    Remove-Item -Recurse -Force $stage
}

Write-Host '==> Done:'
Get-Item $msix | Format-List Name, Length
