$ErrorActionPreference = 'Stop'
$labDir = Join-Path $PSScriptRoot '.local\integration'
# Stop the local recording first so PS/MP4 and Java leases can finish normally.
$state = Invoke-RestMethod 'http://127.0.0.1:19091/api/state'
if ($state.video.active) {
    Invoke-RestMethod -Method Post 'http://127.0.0.1:19091/api/video/stop' -Headers @{'X-Simulator-Request'='1'} -ContentType 'application/json' -Body '{}' | Out-Null
}
foreach ($entry in @(@('bridge','video-integration.mjs'), @('fixture','project-integration.mjs'), @('media','video-integration.mjs'))) {
    $pidPath = Join-Path $labDir ($entry[0] + '.pid')
    if (!(Test-Path -LiteralPath $pidPath)) { continue }
    $ownedId = [int](Get-Content -LiteralPath $pidPath)
    $process = Get-CimInstance Win32_Process -Filter "ProcessId=$ownedId"
    if (!$process) { continue }
    $expectedScript = Join-Path $PSScriptRoot $entry[1]
    if ($process.Name -ne 'node.exe' -or !$process.CommandLine.Contains($expectedScript)) { throw ('PID ownership check failed: ' + $entry[0]) }
    if ($entry[0] -eq 'bridge') {
        [IO.File]::WriteAllText((Join-Path $labDir 'bridge.stop'), [string]$ownedId)
        Wait-Process -Id $ownedId -Timeout 15 -ErrorAction SilentlyContinue
        if (Get-Process -Id $ownedId -ErrorAction SilentlyContinue) { throw 'GB bridge has not finished releasing; inspect its local log before stopping dependencies.' }
        continue
    }
    if ($entry[0] -eq 'fixture') {
        $ffmpegRoot = Join-Path $PSScriptRoot '.local\tools\imageio_ffmpeg\binaries\'
        foreach ($child in @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$ownedId")) {
            if ($child.ExecutablePath -and $child.ExecutablePath.StartsWith($ffmpegRoot) -and $child.Name -like 'ffmpeg*.exe') {
                Stop-Process -Id $child.ProcessId
            }
        }
    }
    Stop-Process -Id $ownedId
}
& (Join-Path $PSScriptRoot 'start-project.ps1') -Stop
$fsPid = Join-Path $labDir 'fs.pid'
if (Test-Path -LiteralPath $fsPid) {
    $ownedId = [int](Get-Content -LiteralPath $fsPid)
    $process = Get-CimInstance Win32_Process -Filter "ProcessId=$ownedId"
    if ($process) {
        if ($process.Name -ne 'FreeSwitchConsole.exe' -or $process.CommandLine -notlike '*fuda-sim-it-media*freeswitch*') { throw 'FreeSWITCH ownership check failed.' }
        Stop-Process -Id $ownedId
    }
}
foreach ($name in @('fuda-sim-it-mysql','fuda-sim-it-redis','fuda-sim-it-zlm','fuda-sim-it-srs')) {
    $raw = docker inspect $name 2>$null
    if ($LASTEXITCODE -ne 0) { continue }
    $container = ($raw | ConvertFrom-Json)[0]
    if ($container.Config.Labels.purpose -ne 'fuda-local-integration' -and $container.Config.Labels.'com.docker.compose.project' -ne 'fuda-sim-it-media') {
        throw ('Container ownership check failed: ' + $name)
    }
    docker stop $name | Out-Null
    if ($LASTEXITCODE -ne 0) { throw ('Cannot stop local container: ' + $name) }
}
Write-Output 'Local integration stopped. Simulator, records, database volumes and original services preserved.'
