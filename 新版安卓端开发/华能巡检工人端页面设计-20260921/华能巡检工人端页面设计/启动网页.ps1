param([int]$Port = 18771, [switch]$NoBrowser, [switch]$Stop)
$ErrorActionPreference = 'Stop'
$url = "http://127.0.0.1:$Port/"
if ($Stop) {
  Invoke-WebRequest -UseBasicParsing -Uri ($url + '__stop') -Method Post -Headers @{'X-Rolling-Preview'='stop'} | Out-Null
  exit
}
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'site'))
if (-not (Test-Path -LiteralPath (Join-Path $root 'index.html'))) { throw 'Static site folder is missing.' }
try {
  $running = Invoke-WebRequest -UseBasicParsing -Uri ($url + '__preview_health') -TimeoutSec 2
  if ($running.Content -eq 'huaneng-worker-preview') {
    if (-not $NoBrowser) { Start-Process $url }
    exit
  }
} catch { }
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($url)
$listener.Start()
if (-not $NoBrowser) { Start-Process $url }
$types = @{'.html'='text/html; charset=utf-8';'.js'='application/javascript; charset=utf-8';'.json'='application/json';'.wasm'='application/wasm';'.png'='image/png';'.jpg'='image/jpeg';'.webp'='image/webp';'.svg'='image/svg+xml';'.ttf'='font/ttf';'.otf'='font/otf';'.woff2'='font/woff2';'.css'='text/css';'.txt'='text/plain; charset=utf-8'}
try {
  while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    try {
      $requestPath = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath)
      if ($requestPath -eq '/__stop' -and $ctx.Request.HttpMethod -eq 'POST' -and $ctx.Request.Headers['X-Rolling-Preview'] -eq 'stop') {
        $ctx.Response.StatusCode = 200
        $ctx.Response.Close()
        break
      }
      if ($requestPath -eq '/__preview_health') {
        $bytes = [Text.Encoding]::UTF8.GetBytes('huaneng-worker-preview')
        $ctx.Response.ContentType = 'text/plain'
      } else {
        if ($ctx.Request.HttpMethod -notin @('GET','HEAD')) { $ctx.Response.StatusCode = 405; $ctx.Response.Close(); continue }
        if ($requestPath -eq '/') { $requestPath = '/index.html' }
        $file = [IO.Path]::GetFullPath((Join-Path $root $requestPath.TrimStart('/')))
        if (-not $file.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or -not [IO.File]::Exists($file)) {
          $ctx.Response.StatusCode = 404; $ctx.Response.Close(); continue
        }
        $bytes = [IO.File]::ReadAllBytes($file)
        $type = $types[[IO.Path]::GetExtension($file).ToLowerInvariant()]
        if (-not $type) { $type = 'application/octet-stream' }
        $ctx.Response.ContentType = $type
      }
      $ctx.Response.Headers['Cache-Control'] = 'no-cache'
      $ctx.Response.ContentLength64 = $bytes.Length
      if ($ctx.Request.HttpMethod -ne 'HEAD') { $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length) }
      $ctx.Response.Close()
    } catch { try { $ctx.Response.Abort() } catch {} }
  }
} finally { $listener.Close() }

