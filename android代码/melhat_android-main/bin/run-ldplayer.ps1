# Real shared backend by default; -Mock is an explicit offline preview.
param([string]$DeviceId, [switch]$Attach, [switch]$Mock, [string]$BackendUrl = 'http://127.0.0.1:18084', [string]$ProxyUrl = $env:HTTPS_PROXY)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$devRoot = if ($env:ANDROID_DEV_HOME) { $env:ANDROID_DEV_HOME } else { 'D:/AndroidDev' }

function Find-Bin($name, $candidates) {
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    $command = Get-Command $name -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    return $null
}

$flutter = Find-Bin 'flutter.bat' @("$devRoot/flutter/bin/flutter.bat")
$adb = Find-Bin 'adb.exe' @("$devRoot/android-sdk/platform-tools/adb.exe", 'D:/Software/leidian/LDPlayer14/adb.exe', 'C:/leidian/LDPlayer14/adb.exe')
if (-not $flutter) { throw 'Flutter not found. Add Flutter bin to PATH.' }
if (-not $adb) { throw 'adb not found. Install Android SDK platform-tools.' }
if (Test-Path "$devRoot/android-sdk") { $env:ANDROID_HOME = "$devRoot/android-sdk"; $env:ANDROID_SDK_ROOT = $env:ANDROID_HOME }
if (Test-Path "$devRoot/pub-cache") { $env:PUB_CACHE = "$devRoot/pub-cache" }
if (Test-Path "$devRoot/gradle-home") { $env:GRADLE_USER_HOME = "$devRoot/gradle-home" }
if (Test-Path "$devRoot/temp") { $env:TEMP = "$devRoot/temp"; $env:TMP = $env:TEMP }
if (-not $env:JAVA_HOME -and (Test-Path "$env:USERPROFILE/.jdks/temurin-17")) { $env:JAVA_HOME = "$env:USERPROFILE/.jdks/temurin-17" }
$env:Path = "$(Split-Path -Parent $flutter);$(Split-Path -Parent $adb);$env:Path"
if ($ProxyUrl) {
    $proxy = [Uri]$ProxyUrl
    if ($proxy.Scheme -ne 'http' -or $proxy.UserInfo -or $proxy.Host -notmatch '^[a-zA-Z0-9.-]+$') {
        throw 'ProxyUrl must be an HTTP proxy URL without credentials.'
    }
    $env:HTTP_PROXY = $ProxyUrl
    $env:HTTPS_PROXY = $ProxyUrl
    $env:NO_PROXY = 'localhost,127.0.0.1'
    $env:GRADLE_OPTS = "$env:GRADLE_OPTS -Dhttp.proxyHost=$($proxy.Host) -Dhttp.proxyPort=$($proxy.Port) -Dhttps.proxyHost=$($proxy.Host) -Dhttps.proxyPort=$($proxy.Port)"
}

if (-not $DeviceId) {
    $devices = @(& $adb devices | ForEach-Object {
        if ($_ -match '^(emulator-\d+|127\.0\.0\.1:\d+)\s+device') { $Matches[1] }
    })
    if ($devices.Count -eq 0) { throw 'Start LDPlayer, then run this script again.' }
    if ($devices.Count -gt 1) { throw 'Multiple emulators found. Specify -DeviceId from adb devices.' }
    $DeviceId = $devices[0]
}

# Use the local ASCII junction only when it points to this checkout.
$buildRoot = $root
$alias = Get-Item -LiteralPath "$devRoot/wearable-android" -ErrorAction SilentlyContinue
if ($alias -and $alias.LinkType -eq 'Junction' -and [IO.Path]::GetFullPath([string](@($alias.Target)[0])).TrimEnd('\') -eq [IO.Path]::GetFullPath($root).TrimEnd('\')) {
    $buildRoot = $alias.FullName
}
$runArgs = if ($Attach) { @('attach', '-d', $DeviceId) } else { @('run', '--debug', '-d', $DeviceId) }
if (-not $Attach) {
    $runArgs += "--dart-define=WEAR_MOCK=$($Mock.IsPresent.ToString().ToLowerInvariant())"
    $runArgs += "--dart-define=WEAR_BACKEND_URL=$BackendUrl"
    if (-not $Mock -and ([Uri]$BackendUrl).Host -in @('localhost','127.0.0.1')) {
        $port = ([Uri]$BackendUrl).Port
        & $adb -s $DeviceId reverse "tcp:$port" "tcp:$port"
        if ($LASTEXITCODE -ne 0) { throw 'ADB reverse failed; backend connection is not ready.' }
    }
}
Push-Location $buildRoot
try {
    & $flutter @runArgs
    if ($LASTEXITCODE -ne 0) { throw 'Flutter run failed.' }
} finally { Pop-Location }
