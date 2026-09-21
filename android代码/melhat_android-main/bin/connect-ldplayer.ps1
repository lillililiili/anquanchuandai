# Verify a direct connection. No adb reverse, root, or NAT rules are created.
param([string]$ApiBaseUrl = "http://10.137.74.38:18084")
$ErrorActionPreference = "Stop"
$ldAdb = "C:\leidian\LDPlayer14\adb.exe"
if (-not (Test-Path $ldAdb)) { throw "LDPlayer adb not found: $ldAdb" }
$uri = [Uri]$ApiBaseUrl
if ($uri.Scheme -notin @("http", "https") -or $uri.Host -in @("localhost", "127.0.0.1", "::1", "10.0.2.2")) {
    throw "Use the computer's reachable network IP or backend domain, not a loopback/emulator alias."
}
$device = & $ldAdb devices |
    ForEach-Object { if ($_ -match '^(emulator-\d+|127\.0\.0\.1:\d+)\s+device') { $Matches[1] } } |
    Select-Object -First 1
if (-not $device) { throw "No emulator connected. Start LDPlayer first." }
$health = & $ldAdb -s $device shell curl -fsS -m 8 ($ApiBaseUrl.TrimEnd("/") + "/actuator/health")
if ($LASTEXITCODE -ne 0 -or "$health" -notmatch '"status"\s*:\s*"UP"') {
    throw "The emulator cannot directly reach $ApiBaseUrl. Check the backend, network and firewall."
}
Write-Output "Direct backend OK: device=$device url=$ApiBaseUrl"
