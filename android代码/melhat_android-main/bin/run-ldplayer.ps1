# Run against a directly reachable backend without adb reverse.
param([string]$ApiBaseUrl = "http://10.137.74.38:18084")
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

function Find-Bin($name, $fallback) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    if ($fallback -and (Test-Path $fallback)) { return $fallback }
    return $null
}

$adb = Find-Bin "adb.exe" "C:\leidian\LDPlayer14\adb.exe"
$flutter = Find-Bin "flutter.bat" "C:\melhat-runtime\flutter\bin\flutter.bat"
if (-not $flutter) { $flutter = Find-Bin "flutter" $null }
if (-not $adb) { throw "adb not found. Add Android SDK platform-tools to PATH." }
if (-not $flutter) { throw "flutter not found. Add Flutter to PATH." }

$device = & $adb devices | ForEach-Object {
    if ($_ -match '^(emulator-\d+|127\.0\.0\.1:\d+)\s+device') { $Matches[1] }
} | Select-Object -First 1
if (-not $device) { throw "No emulator found. Start the emulator first." }

& (Join-Path $PSScriptRoot "connect-ldplayer.ps1") -ApiBaseUrl $ApiBaseUrl
# The existing junction avoids native plugin build failures with non-ASCII paths.
$buildRoot = "C:\melhat-runtime\wearable-android"
if (-not (Test-Path $buildRoot)) { $buildRoot = $root }
if (-not $env:GRADLE_USER_HOME -and (Test-Path "C:\melhat-runtime\gradle-home")) {
    $env:GRADLE_USER_HOME = "C:\melhat-runtime\gradle-home"
}
Push-Location $buildRoot
try {
    & $flutter run -d $device "--dart-define=API_BASE_URL=$ApiBaseUrl" --dart-define=CALL_LAB_ENABLED=true
    if ($LASTEXITCODE -ne 0) { throw "Flutter run failed." }
} finally { Pop-Location }
