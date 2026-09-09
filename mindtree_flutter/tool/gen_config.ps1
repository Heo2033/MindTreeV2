# Generates mindtree_flutter/provider-config.json from server/.env so the
# Flutter app can be built/run in "hardcoded" provider mode (the default):
#
#   & tool\gen_config.ps1
#   flutter build windows --dart-define-from-file=provider-config.json
#
# Add -Configurable to emit PROVIDER_MODE=configurable so the in-app provider
# settings form actually applies (overrides stored in SharedPreferences/secure
# storage) instead of using the build-time pinned values:
#
#   & tool\gen_config.ps1 -Configurable
#
# The generated file contains the secret LLM API key and is gitignored.
param(
    [switch]$Configurable
)

$ErrorActionPreference = 'Stop'

$envFile = Join-Path $PSScriptRoot '..\..\server\.env'
$outFile = Join-Path $PSScriptRoot '..\provider-config.json'

if (-not (Test-Path $envFile)) {
    Write-Error "Not found: $envFile"
}

function Read-EnvValue([string]$Key) {
    $line = Get-Content $envFile | Where-Object { $_ -match "^\s*$Key=" } | Select-Object -First 1
    if (-not $line) { return '' }
    return ($line -replace "^\s*$Key=", '').Trim()
}

$cfg = [ordered]@{
    PROVIDER_MODE            = if ($Configurable) { 'configurable' } else { 'hardcoded' }
    LLM_BASE_URL             = Read-EnvValue 'LLM_BASE_URL'
    LLM_API_KEY              = Read-EnvValue 'LLM_API_KEY'
    LLM_MODEL                = Read-EnvValue 'LLM_MODEL'
    LLM_MODEL_STRONG         = Read-EnvValue 'LLM_MODEL_STRONG'
    LLM_MODEL_STRONG_FALLBACK = Read-EnvValue 'LLM_MODEL_STRONG_FALLBACK'
    LLM_MODEL_FAST           = Read-EnvValue 'LLM_MODEL_FAST'
    LLM_PROVIDER             = 'auto'
    LLM_TEMPERATURE          = '0.7'
    LLM_NUM_CTX              = '8192'
}

$json = $cfg | ConvertTo-Json
Set-Content -Path $outFile -Value $json -Encoding UTF8

$masked = if ($cfg.LLM_API_KEY) { "present ($($cfg.LLM_API_KEY.Length) chars)" } else { 'MISSING' }
Write-Host "Wrote $outFile"
Write-Host "  mode    = $($cfg.PROVIDER_MODE)"
Write-Host "  baseUrl = $($cfg.LLM_BASE_URL)"
Write-Host "  model   = $($cfg.LLM_MODEL)"
Write-Host "  strong  = $($cfg.LLM_MODEL_STRONG)"
Write-Host "  strongF = $($cfg.LLM_MODEL_STRONG_FALLBACK)"
Write-Host "  fast    = $($cfg.LLM_MODEL_FAST)"
Write-Host "  apiKey  = $masked"