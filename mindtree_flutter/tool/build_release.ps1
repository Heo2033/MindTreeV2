# Release Windows build, packed into dist\mindtree_windows-<version>.zip
#
# Usage (from repo root or mindtree_flutter):
#   powershell -ExecutionPolicy Bypass -File mindtree_flutter\tool\build_release.ps1
#
# Options:
#   -NoBuild   - skip rebuild, pack the existing Release output only.

param(
    [switch]$NoBuild
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if (-not $NoBuild) {
    & 'C:\flutter\bin\flutter.bat' build windows --release
    if (-not $?) { Write-Error 'flutter build windows --release failed.'; exit 1 }
}

$releaseDir = Join-Path $root 'build\windows\x64\runner\Release'
if (-not (Test-Path -LiteralPath $releaseDir)) {
    Write-Error "Release dir missing: $releaseDir (run without -NoBuild)."
    exit 1
}

$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Path $dist -Force | Out-Null

$version = (Select-String -LiteralPath (Join-Path $root 'pubspec.yaml') -Pattern '^version:\s*(\S+)' |
    ForEach-Object { $_.Matches[0].Groups[1].Value }).Trim()
if (-not $version) { $version = 'unknown' }

$zip = Join-Path $dist "mindtree_windows-$version.zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip }

Compress-Archive -Path (Join-Path $releaseDir '*') -DestinationPath $zip -Force

Write-Output "Done: $zip"

# Android: copy release APK if present (built separately via flutter build apk --release).
$apk = Join-Path $root 'build\app\outputs\flutter-apk\app-release.apk'
if (Test-Path -LiteralPath $apk) {
    $apkOut = Join-Path $dist "mindtree_android-$version.apk"
    Copy-Item -LiteralPath $apk -Destination $apkOut -Force
    Write-Output "Done: $apkOut"
}