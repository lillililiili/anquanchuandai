# Map the debug APK's default http://10.0.2.2:18084 onto the PC backend
# for LDPlayer (雷电), which cannot reach 10.0.2.2.
# Run this after starting LDPlayer. Requires the instance to be rooted
# (this project's LDPlayer config already has rootMode=true).
$ErrorActionPreference = "Stop"
$ldAdb = "C:\leidian\LDPlayer14\adb.exe"
if (-not (Test-Path $ldAdb)) { throw "LDPlayer adb not found: $ldAdb" }

& $ldAdb start-server | Out-Null
$device = & $ldAdb devices |
    ForEach-Object { if ($_ -match '^(emulator-\d+|127\.0\.0\.1:\d+)\s+device') { $Matches[1] } } |
    Select-Object -First 1
if (-not $device) { throw "No LDPlayer device. Start 雷电模拟器 first." }

& $ldAdb -s $device reverse tcp:18084 tcp:18084 | Out-Null
& $ldAdb -s $device root | Out-Null
Start-Sleep -Seconds 1
& $ldAdb -s $device shell "iptables -t nat -D OUTPUT -p tcp -d 10.0.2.2 --dport 18084 -j REDIRECT --to-ports 18084 2>/dev/null; iptables -t nat -A OUTPUT -p tcp -d 10.0.2.2 --dport 18084 -j REDIRECT --to-ports 18084"

$health = & $ldAdb -s $device shell "curl -s -m 4 http://10.0.2.2:18084/actuator/health"
Write-Output "device=$device"
Write-Output "health=$health"
if ($health -notmatch '"status"\s*:\s*"UP"') {
    throw "Backend not reachable from LDPlayer. Is docker compose up on port 18084?"
}
Write-Output "LDPlayer -> http://10.0.2.2:18084 is mapped to this PC :18084"
