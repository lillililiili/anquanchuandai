param(
    [Parameter(Mandatory=$true)][string]$ConnectionFile,
    [Parameter(Mandatory=$true)][string]$RedisFile,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [string]$JavaHome = 'D:/DevTools/jdk-17.0.20.1+1',
    [string]$Maven = 'D:/DevTools/apache-maven-3.9.16/bin/mvn.cmd'
)
$ErrorActionPreference = 'Stop'
$configPath = (Resolve-Path -LiteralPath $ConnectionFile).Path
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$redisPath = (Resolve-Path -LiteralPath $RedisFile).Path
$redis = Get-Content -LiteralPath $redisPath -Raw | ConvertFrom-Json
if ($config.username -notin @('WEARABLE_TEST','wearable_test') -or $redis.port -ne 16379) { throw 'Only the isolated test schemas and Redis 16379 db3 may run this destructive fixture.' }
$env:JAVA_HOME = $JavaHome
$env:ROUTING_CONNECTION_FILE = $configPath
$env:COORDINATION_REDIS_FILE = $redisPath
$env:COORDINATION_OUTPUT = (Resolve-Path -LiteralPath $OutputDirectory).Path
Push-Location -LiteralPath (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../../..')).Path
try {
    & $Maven -B -pl ruoyi-admin -am '-Dtest=RealCoordinationProcessTest' '-Dsurefire.failIfNoSpecifiedTests=false' '-DargLine=-Xmx512m -Djdk.net.unixdomain.tmpdir=D:/DevTools/dm8-tmp -Djava.io.tmpdir=D:/DevTools/dm8-tmp' test
    if ($LASTEXITCODE -ne 0) { throw "Coordination tests failed with exit code $LASTEXITCODE" }
} finally { Pop-Location }
# Evidence contains actual JVM PID, port, generation and assertions, never credentials.
# Only test schema rows and Redis db3 test keys are written; children terminate in finally.
