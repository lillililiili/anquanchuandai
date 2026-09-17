# Map the debug APK's default http://10.0.2.2:18084 onto the PC backend
# for LDPlayer (雷电), which cannot reach 10.0.2.2.
# Run this after starting LDPlayer. Requires the instance to be rooted
# (this project's LDPlayer config already has rootMode=true).
$ErrorActionPreference = "Stop"
$ldAdb = "C:\leidian\LDPlayer14\adb.exe"
if (-not (Test-Path $ldAdb)) { throw "LDPlayer adb not found: $ldAdb" }

& $ldAdb start-server | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Could not start LDPlayer adb." }
$device = & $ldAdb devices |
    ForEach-Object { if ($_ -match '^(emulator-\d+|127\.0\.0\.1:\d+)\s+device') { $Matches[1] } } |
    Select-Object -First 1
if (-not $device) { throw "No LDPlayer device. Start 雷电模拟器 first." }

# root restarts adbd and can discard reverse mappings. Always map AFTER it.
& $ldAdb -s $device root | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Could not restart adb as root." }
& $ldAdb -s $device wait-for-device
if ($LASTEXITCODE -ne 0) { throw "LDPlayer did not reconnect." }
$uid = & $ldAdb -s $device shell id -u
if ($LASTEXITCODE -ne 0 -or "$uid".Trim() -ne "0") {
    throw "This APK uses 10.0.2.2. Enable LDPlayer root, or use run-ldplayer.ps1 to build with 127.0.0.1 instead."
}

& $ldAdb -s $device reverse tcp:18084 tcp:18084 | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Could not forward backend port 18084." }
# Idempotent: repeated runs must not accumulate NAT rules.
& $ldAdb -s $device shell "iptables -t nat -C OUTPUT -p tcp -d 10.0.2.2 --dport 18084 -j REDIRECT --to-ports 18084 2>/dev/null || iptables -t nat -A OUTPUT -p tcp -d 10.0.2.2 --dport 18084 -j REDIRECT --to-ports 18084"
if ($LASTEXITCODE -ne 0) { throw "Could not map 10.0.2.2 to the forwarded backend port." }

$health = & $ldAdb -s $device shell "curl -fsS -m 5 http://10.0.2.2:18084/actuator/health"
$healthExit = $LASTEXITCODE
Write-Output "device=$device"
Write-Output "health=$health"
if ($healthExit -ne 0 -or $health -notmatch '"status"\s*:\s*"UP"') {
    throw "Backend not reachable from LDPlayer. Is docker compose up on port 18084?"
}
Write-Output "LDPlayer -> http://10.0.2.2:18084 is mapped to this PC :18084"
