# Живой A/B v2: контент-пул + кламп one_liner + maxConcurrency=4.
# Запуск в фоне: Start-Process powershell -ArgumentList ... -WindowStyle Hidden
# Кириллица в query — одинарные кавычки (см. AGENTS.md про PowerShell).
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$dart = 'C:\flutter\bin\cache\dart-sdk\bin\dart.exe'
$runDir = 'C:\home\projects\MindTreeV2\mindtree_flutter'
$out = Join-Path $runDir 'build\probe-live-v2'
if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Recurse -Force }
New-Item -ItemType Directory -Path $out -Force | Out-Null
$query = 'диффузионные модели'
$log = Join-Path $out 'run.log'
& $dart run 'tool\probe\bin\mindtree_probe.dart' --query $query --level 3 --concurrency 4 --out $out *> $log
$code = $LASTEXITCODE
Write-Output "EXITCODE=$code" | Out-File -FilePath (Join-Path $out 'done.txt') -Encoding ascii
exit $code