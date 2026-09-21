param([string]$Flutter = 'flutter')
$ErrorActionPreference = 'Stop'
# Build only the isolated copy inside this display directory.
$source = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '展示源码'))
if (-not $source.StartsWith([IO.Path]::GetFullPath($PSScriptRoot) + [IO.Path]::DirectorySeparatorChar)) { throw 'Invalid display source path.' }
if (-not (Test-Path -LiteralPath (Join-Path $source 'pubspec.yaml'))) { throw 'Rebuild from the full display project containing the isolated source.' }
if ($Flutter -eq 'flutter' -and -not (Get-Command flutter -ErrorAction SilentlyContinue)) { $Flutter = 'C:/melhat-runtime/flutter/bin/flutter.bat' }
if (-not $env:PUB_CACHE -and (Test-Path -LiteralPath 'C:/melhat-runtime/pub-cache')) { $env:PUB_CACHE = 'C:/melhat-runtime/pub-cache' }
if (-not $env:PUB_HOSTED_URL) { $env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn' }
Push-Location $source
try {
  & $Flutter pub get --offline
  if ($LASTEXITCODE -ne 0) { throw 'Dependencies are missing from the local Flutter cache.' }
  & $Flutter build web --release --no-pub --target lib/web_preview/main.dart --dart-define=CALL_LAB_ENABLED=true --no-web-resources-cdn --no-wasm-dry-run
  if ($LASTEXITCODE -ne 0) { throw 'Flutter web build failed.' }
  $output = Join-Path $PSScriptRoot 'site'
  New-Item -ItemType Directory -Force $output | Out-Null
  $buildRoot = Join-Path $source 'build/web'
  foreach ($file in (Get-ChildItem -LiteralPath $buildRoot -Recurse -File -Force)) {
    $destination = Join-Path $output $file.FullName.Substring($buildRoot.Length+1)
    New-Item -ItemType Directory -Force (Split-Path $destination -Parent) | Out-Null
    if ((Test-Path -LiteralPath $destination) -and (Get-FileHash -LiteralPath $destination).Hash -eq (Get-FileHash -LiteralPath $file.FullName).Hash) { continue }
    for ($attempt=0; $attempt -lt 4; $attempt++) {
      try { Copy-Item -LiteralPath $file.FullName -Destination $destination -Force; break }
      catch { if ($attempt -eq 3) { throw }; Start-Sleep -Milliseconds 300 }
    }
  }
  $fontPath = Join-Path $output 'assets/FontManifest.json'
  $parsedFonts = ConvertFrom-Json ([IO.File]::ReadAllText($fontPath, [Text.Encoding]::UTF8))
  $fonts = @()
  foreach ($font in $parsedFonts) {
    if ($font.family -ne 'Roboto') {
      $entries = @()
      foreach ($entry in $font.fonts) { $entries += @{asset=[string]$entry.asset} }
      $fonts += @{family=[string]$font.family;fonts=$entries}
    }
  }
  $fonts += @{family='Roboto';fonts=@(@{asset='../fonts/NotoSansCJKsc-Regular.otf'})}
  $utf8 = New-Object Text.UTF8Encoding($false)
  [IO.File]::WriteAllText($fontPath, (ConvertTo-Json -InputObject $fonts -Depth 6), $utf8)
  $baseline = Get-Content -LiteralPath (Join-Path $PSScriptRoot '同步验收/20260921/主项目只读快照.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  $info = @{builtAt=(Get-Date).ToString('o');source=$baseline.source;sourceCapturedAt=$baseline.capturedAt;sourceFiles=$baseline.files;isolatedBuild=$true;callLabEnabled=$true;dataMode='Local snapshot; all actions in memory';mainJsSha256=(Get-FileHash -LiteralPath (Join-Path $output 'main.dart.js') -Algorithm SHA256).Hash.ToLowerInvariant()}
  [IO.File]::WriteAllText((Join-Path $output 'build-info.json'),($info | ConvertTo-Json -Depth 6),$utf8)
  $hashes = @(Get-ChildItem -LiteralPath $output -Recurse -File | ForEach-Object { @{path=$_.FullName.Substring($PSScriptRoot.Length+1).Replace('\','/');sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()} })
  [IO.File]::WriteAllText((Join-Path $PSScriptRoot '文件校验清单.json'),(ConvertTo-Json -InputObject $hashes -Depth 5),$utf8)
  Write-Output "Display updated: $output"
} finally { Pop-Location }
