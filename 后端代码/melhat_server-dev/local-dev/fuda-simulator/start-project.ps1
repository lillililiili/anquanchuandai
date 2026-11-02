param([string]$JavaPath = 'D:\DevTools\jdk-17.0.20.1+1\bin\java.exe', [switch]$Restart, [switch]$Stop)
$ErrorActionPreference = 'Stop'
$labDir = Join-Path $PSScriptRoot '.local\integration'
$configPath = Join-Path $labDir 'application.yml'
$pidPath = Join-Path $labDir 'java.pid'
if ($Restart -or $Stop) {
    if (Test-Path -LiteralPath $pidPath) {
        $labProcessId = [int](Get-Content -LiteralPath $pidPath)
        $process = Get-CimInstance Win32_Process -Filter "ProcessId=$labProcessId"
        if ($process) {
            if ($process.Name -ne 'java.exe' -or !$process.CommandLine.Contains($configPath.Replace('\','/'))) {
                throw 'PID does not belong to this local integration instance; refusing to stop it.'
            }
            Stop-Process -Id $labProcessId
            Wait-Process -Id $labProcessId -Timeout 15 -ErrorAction SilentlyContinue
        }
    }
    if ($Stop) { return }
}
if (!(Test-Path -LiteralPath $configPath)) { throw 'Run prepare-project.py configure first.' }
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
if ($config.server.address -ne '127.0.0.1' -or $config.server.port -ne 18095 -or
    $config.spring.datasource.druid.master.url -notlike 'jdbc:mysql://127.0.0.1:13316/fuda_sim_it?*' -or
    $config.fuda.push.endpoint -ne 'http://127.0.0.1:19092/receive') { throw 'Local lab endpoint guard failed.' }
if (Get-NetTCPConnection -LocalPort 18095 -State Listen -ErrorAction SilentlyContinue) { throw '18095 is already in use.' }
$backend = Split-Path (Split-Path $PSScriptRoot)
$jarPath = Join-Path $backend 'ruoyi-admin\target\fdc-admin.jar'
$private = Get-Content -LiteralPath (Join-Path $labDir 'java-config.json') -Raw | ConvertFrom-Json
if ((Get-FileHash -LiteralPath $jarPath).Hash.ToLowerInvariant() -ne $private.jarSha256) { throw 'Candidate JAR changed; verify it before updating the lab manifest.' }
$tempDir = Join-Path ([IO.Path]::GetPathRoot($PSScriptRoot)) 'fuda-sim-it-tmp'
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
$javaArgs = @('-Xms128m','-Xmx512m','-Dfile.encoding=UTF-8',
    ('"-Djava.io.tmpdir=' + $tempDir + '"'), ('"-Djdk.net.unixdomain.tmpdir=' + $tempDir + '"'),
    ('"-Djavax.net.ssl.trustStore=' + (Join-Path $labDir 'truststore.p12') + '"'),
    '-Djavax.net.ssl.trustStorePassword=local-test-trust', '-jar', ('"' + $jarPath + '"'),
    ('"--spring.config.additional-location=file:' + $configPath.Replace('\','/') + '"'))
$started = Start-Process -FilePath $JavaPath -ArgumentList $javaArgs -WorkingDirectory $labDir -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $labDir 'java.stdout.log') -RedirectStandardError (Join-Path $labDir 'java.stderr.log')
$started.Id | Set-Content -LiteralPath $pidPath
Write-Output ('Local integration Java PID: ' + $started.Id)
