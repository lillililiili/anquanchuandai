param([switch]$SkipBuild)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
if (!(Test-Path -LiteralPath '.env')) { & ./Initialize.ps1 }
if (!$SkipBuild) {
  Push-Location ..
  try { & mvn -pl ruoyi-admin -am package '-DskipTests' -q; if ($LASTEXITCODE -ne 0) { throw 'Backend build failed' } } finally { Pop-Location }
}
& docker compose --env-file .env -f compose.yml -p wearable-portal-demo up -d --build
if ($LASTEXITCODE -ne 0) { throw 'Demo start failed; check ports 13308,6381,18085. Original services were not changed.' }
