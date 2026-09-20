$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
if (Test-Path -LiteralPath '.env') { Write-Host 'Configuration already exists; credentials were not overwritten.'; exit 0 }
function New-Secret {
  $bytes = New-Object byte[] 32
  $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
  return ([BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
}
New-Item -ItemType Directory -Force -Path 'runtime','backups' | Out-Null
$settings = @(('DEMO_DB_PASSWORD=' + (New-Secret)), ('DEMO_ROOT_PASSWORD=' + (New-Secret)), ('DEMO_TOKEN_SECRET=' + (New-Secret)))
[IO.File]::WriteAllLines((Join-Path $PSScriptRoot '.env'), $settings)
Write-Host 'Created isolated local credentials. Do not commit .env or runtime/.'
