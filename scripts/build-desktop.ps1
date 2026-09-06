# Сборка автономного десктопного приложения (один exe):
# 1. Собирает самодостаточный sidecar с сервером (dist + node_modules + node.exe)
# 2. Запускает `tauri build` (перед ним собирается фронтенд через beforeBuildCommand)
#
# Требования: соберите на целевой платформе (Windows), чтобы node.exe и
# нативный better-sqlite3 соответствовали целевой архитектуре.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot

Write-Host "`n[1/2] Building server sidecar..." -ForegroundColor Cyan
Push-Location (Join-Path $Root "server")
try {
    node build-sidecar.mjs
    if ($LASTEXITCODE -ne 0) { throw "sidecar build failed" }
} finally {
    Pop-Location
}

Write-Host "`n[2/2] Building desktop app (tauri build)..." -ForegroundColor Cyan
Push-Location (Join-Path $Root "apps/desktop")
try {
    npm run build
    if ($LASTEXITCODE -ne 0) { throw "tauri build failed" }
} finally {
    Pop-Location
}

Write-Host "`nDone. Installer/bundle in apps/desktop/src-tauri/target/release/bundle/" -ForegroundColor Green