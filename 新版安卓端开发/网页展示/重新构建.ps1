param([string]$Flutter = 'flutter')
$ErrorActionPreference = 'Stop'
$project = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$android = Join-Path $project 'android代码/melhat_android-main'
if ($Flutter -eq 'flutter' -and -not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  if (Test-Path -LiteralPath 'C:/melhat-runtime/flutter/bin/flutter.bat') {
    $Flutter = 'C:/melhat-runtime/flutter/bin/flutter.bat'
  }
}
if (-not $env:PUB_CACHE -and (Test-Path -LiteralPath 'C:/melhat-runtime/pub-cache')) {
  $env:PUB_CACHE = 'C:/melhat-runtime/pub-cache'
}
Push-Location $android
try {
  & $Flutter build web --release --no-pub --target lib/web_preview/main.dart --no-web-resources-cdn --no-wasm-dry-run
  if ($LASTEXITCODE -ne 0) { throw 'Flutter web build failed.' }
  # Register the bundled CJK font before CanvasKit initializes its default
  # Roboto fallback. Loading it only in main() is too late to avoid CDN fetches.
  $fontManifestPath = Join-Path $android 'build/web/assets/FontManifest.json'
  $fontManifest = @(Get-Content -LiteralPath $fontManifestPath -Raw | ConvertFrom-Json | Where-Object { $_.family -ne 'Roboto' })
  $fontManifest += @{ family = 'Roboto'; fonts = @(@{ asset = '../fonts/NotoSansCJKsc-Regular.otf' }) }
  [IO.File]::WriteAllText($fontManifestPath, (ConvertTo-Json -InputObject $fontManifest -Depth 6 -Compress), (New-Object Text.UTF8Encoding($false)))
  $output = Join-Path $PSScriptRoot 'site'
  New-Item -ItemType Directory -Force $output | Out-Null
  Get-ChildItem -LiteralPath (Join-Path $android 'build/web') -Force | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $output -Recurse -Force
  }
  $sourceFiles = @(
    Get-ChildItem -LiteralPath (Join-Path $android 'lib'), (Join-Path $android 'assets'), (Join-Path $android 'web') -Recurse -File
    Get-Item -LiteralPath (Join-Path $android 'pubspec.yaml'), (Join-Path $android 'pubspec.lock')
  )
  $sourceHashes = @($sourceFiles | Sort-Object FullName | ForEach-Object {
    @{ path = $_.FullName.Substring($android.Length + 1).Replace('\','/'); sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
  })
  $buildInfo = @{
    builtAt = (Get-Date).ToString('o')
    sourceCommit = (& git rev-parse --short HEAD)
    source = 'Current Android working tree, including local changes'
    entrypoint = 'lib/web_preview/main.dart'
    dataMode = 'Local preview data; no production server or real devices'
    sourceFiles = $sourceHashes
    mainJsSha256 = (Get-FileHash -LiteralPath (Join-Path $output 'main.dart.js') -Algorithm SHA256).Hash.ToLowerInvariant()
  }
  [IO.File]::WriteAllText((Join-Path $output 'build-info.json'), ($buildInfo | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))
  $outputHashes = @(Get-ChildItem -LiteralPath $output -Recurse -File -Force | Sort-Object FullName | ForEach-Object {
    @{ path = $_.FullName.Substring($PSScriptRoot.Length + 1).Replace('\','/'); sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
  })
  [IO.File]::WriteAllText((Join-Path $PSScriptRoot '文件校验清单.json'), ($outputHashes | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))
  Write-Output "Updated current Android web preview: $output"
} finally { Pop-Location }

