param(
    [Parameter(Mandatory=$true)][string]$ConnectionFile,
    [string]$JavaHome = 'D:/DevTools/jdk-17.0.20.1+1',
    [string]$Maven = 'D:/DevTools/apache-maven-3.9.16/bin/mvn.cmd',
    [switch]$ResetClusterSchema
)
$ErrorActionPreference = 'Stop'
$configPath = (Resolve-Path -LiteralPath $ConnectionFile).Path
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
if ($config.username -notin @('WEARABLE_TEST','wearable_test')) {
    throw 'Only WEARABLE_TEST / wearable_test may run this destructive synthetic fixture.'
}
$backendPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../../..')).Path
$env:JAVA_HOME = $JavaHome
$env:ROUTING_CONNECTION_FILE = $configPath
$env:ROUTING_RESET_CLUSTER_SCHEMA = if ($ResetClusterSchema) { 'true' } else { 'false' }
Push-Location -LiteralPath $backendPath
try {
    & $Maven -B -pl ruoyi-admin -am '-Dtest=ClusterRoutingContractTest,ClusterMediaIntegrationTest,RealClusterProcessTest' '-Dsurefire.failIfNoSpecifiedTests=false' '-DargLine=-Djdk.net.unixdomain.tmpdir=D:/DevTools/dm8-tmp -Djava.io.tmpdir=D:/DevTools/dm8-tmp' test
    if ($LASTEXITCODE -ne 0) { throw "Routing contract tests failed with exit code $LASTEXITCODE" }
} finally { Pop-Location }
# RealClusterProcessTest prints CLUSTER_EVIDENCE with PID/port/barrier/command-state artifacts.
# The fixture starts loopback-only synthetic Spring/WS processes, and always terminates them.
