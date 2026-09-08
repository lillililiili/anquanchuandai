# Optional helper for LDPlayer / any emulator that needs adb reverse.
# Default `flutter run` is unchanged: official AVD still uses http://10.0.2.2:18084.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

function Find-Bin($name, $fallback) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    if ($fallback -and (Test-Path $fallback)) { return $fallback }
    return $null
}

$adb = Find-Bin "adb.exe" (Join-Path ($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT | Where-Object { $_ } | Select-Object -First 1) "platform-tools\adb.exe")
$flutter = Find-Bin "flutter.bat" $null
if (-not $flutter) { $flutter = Find-Bin "flutter" $null }
if (-not $adb) { throw "adb not found. Add Android SDK platform-tools to PATH." }
if (-not $flutter) { throw "flutter not found. Add Flutter to PATH." }

$device = & $adb devices | ForEach-Object {
    if ($_ -match '^(emulator-\d+|127\.0\.0\.1:\d+)\s+device') { $Matches[1] }
} | Select-Object -First 1
if (-not $device) { throw "No emulator found. Start the emulator first." }

& $adb -s $device reverse tcp:18084 tcp:18084
Set-Location $root
& $flutter run -d $device --dart-define=API_BASE_URL=http://127.0.0.1:18084
