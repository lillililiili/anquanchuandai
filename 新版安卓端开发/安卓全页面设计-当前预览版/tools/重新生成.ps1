param(
  [string]$Flutter = 'C:/melhat-runtime/flutter/bin/flutter.bat',
  [string]$Python = 'C:/Users/qiyue/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
)
$ErrorActionPreference = 'Stop'
$previewRoot = Split-Path $PSScriptRoot -Parent
$projectRoot = Split-Path (Split-Path $previewRoot -Parent) -Parent
$androidRoot = Join-Path $projectRoot 'android代码/melhat_android-main'
$env:PREVIEW_OUTPUT_ROOT = $previewRoot
$env:PYTHONUTF8 = '1'
$env:PUB_CACHE = 'C:/melhat-runtime/pub-cache'
Push-Location $androidRoot
try {
  foreach ($number in 1..42) {
    $captureId = $number.ToString('00')
    $log = Join-Path $PSScriptRoot "capture-$captureId.log"
    & $Flutter test --no-pub (Join-Path $PSScriptRoot 'capture_test.dart') --plain-name "capture $captureId" --reporter expanded *> $log
    if ($LASTEXITCODE -ne 0) { throw "Capture $captureId failed. Read $log" }
    Write-Output "Captured $captureId / 42"
  }
} finally { Pop-Location }
& $Python (Join-Path $PSScriptRoot 'build_gallery.py')
if ($LASTEXITCODE -ne 0) { throw 'Gallery build failed.' }
Write-Output "Open $previewRoot/index.html"
