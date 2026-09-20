$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
& docker compose --env-file .env -f compose.yml -p wearable-portal-demo stop
if ($LASTEXITCODE -ne 0) { throw 'Demo stop failed' }
