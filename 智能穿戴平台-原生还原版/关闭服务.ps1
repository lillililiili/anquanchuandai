param([switch]$LocalOnly)
$ErrorActionPreference = 'Stop'
$entry = Join-Path $PSScriptRoot 'server.js'
$previewProcesses = @(Get-CimInstance Win32_Process -Filter "Name='node.exe'" | Where-Object { $_.CommandLine -and $_.CommandLine.IndexOf($entry, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
# 兼容旧版以相对路径启动的服务：同时核对端口、程序和页面内容。
foreach ($previewPort in $(if($LocalOnly){@(5188)}else{@(5188,5193)})) {
  try {
    $listeners = @(Get-NetTCPConnection -LocalPort $previewPort -State Listen -ErrorAction Stop)
    $page = Invoke-WebRequest -Uri ("http://127.0.0.1:" + $previewPort + "/index.html") -UseBasicParsing -TimeoutSec 2
    $expected = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'index.html'))
    if ($page.Content -cne $expected) { continue }
    foreach ($listener in $listeners) {
      $process = Get-CimInstance Win32_Process -Filter ("ProcessId=" + $listener.OwningProcess)
      if ($process.Name -eq 'node.exe' -and $process.CommandLine -match '(?:^|\s)"?server\.js"?(?:\s|$)' -and $process.ProcessId -notin $previewProcesses.ProcessId) { $previewProcesses += $process }
    }
  } catch { }
}
if ($LocalOnly) { $previewProcesses = @($previewProcesses | Where-Object { $_.CommandLine -notmatch '--share' }) }
# 隧道独立于网页服务运行；核对本目录记录的 PID 和目标端口后关闭。
if (-not $LocalOnly) {
  $tunnelPidFile = Join-Path $PSScriptRoot '.share\tunnel.pid'
  if (Test-Path -LiteralPath $tunnelPidFile) {
    $tunnelProcessId = 0
    if ([int]::TryParse(([IO.File]::ReadAllText($tunnelPidFile)).Trim(), [ref]$tunnelProcessId)) {
      $tunnelProcess = Get-CimInstance Win32_Process -Filter ("ProcessId=" + $tunnelProcessId)
      if ($tunnelProcess -and $tunnelProcess.Name -eq 'cloudflared.exe' -and $tunnelProcess.CommandLine -match '--url\s+http://127\.0\.0\.1:5193(?:\s|$)') {
        $previewProcesses += $tunnelProcess
      }
    }
  }
}
if ($previewProcesses.Count -eq 0) { Write-Host '本目录原型服务未运行，或旧服务使用了相对路径启动。'; exit 0 }
foreach ($item in $previewProcesses) {
  & taskkill.exe /PID $item.ProcessId /T /F | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "无法关闭进程 $($item.ProcessId)" }
  Write-Host ('已关闭本目录原型服务，进程：' + $item.ProcessId)
}
