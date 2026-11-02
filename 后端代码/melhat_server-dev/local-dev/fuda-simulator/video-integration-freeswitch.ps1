param([string]$AsciiJunction = 'D:\fuda-sim-it-media')
$ErrorActionPreference = 'Stop'
$integrationRoot = Join-Path $PSScriptRoot '.local\integration'
if (!(Test-Path -LiteralPath (Join-Path $integrationRoot 'media-config.json'))) { throw 'Run node video-integration.mjs prepare first.' }
$integrationRoot = (Resolve-Path -LiteralPath $integrationRoot).Path
# FreeSWITCH Windows cannot open the project's Unicode paths. This junction points
# only at this isolated ignored directory; there are no service/system installs.
if (Test-Path -LiteralPath $AsciiJunction) {
    $item = Get-Item -LiteralPath $AsciiJunction
    if ($item.LinkType -ne 'Junction' -or $item.Target -ne $integrationRoot) { throw 'Existing junction is not this integration directory.' }
} else { New-Item -ItemType Junction -Path $AsciiJunction -Target $integrationRoot | Out-Null }
if ($AsciiJunction -match '[^\x00-\x7F]') { throw 'FreeSWITCH requires an ASCII junction path.' }
$package = Join-Path $integrationRoot 'FreeSWITCH-1.11.3-Release-x64.msi'
$sha256 = 'F5649E33AD46BE2EBDB1D98019BD149C86519F0DCA9F47FB881207045203A34D'
if (!(Test-Path -LiteralPath $package)) {
    Invoke-WebRequest 'https://github.com/signalwire/freeswitch/releases/download/v1.11.3/FreeSWITCH-1.11.3-Release-x64.msi' -OutFile $package
}
if ((Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash -ne $sha256) { throw 'Official release digest mismatch.' }
$native = Join-Path $AsciiJunction 'freeswitch-native'
$exe = Get-ChildItem -LiteralPath $native -Filter FreeSwitchConsole.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if (!$exe) {
    $arguments = '/a "' + $package + '" /qn TARGETDIR="' + $native + '" /L*v "' + (Join-Path $integrationRoot 'freeswitch-extract.log') + '"'
    $extract = Start-Process msiexec.exe -ArgumentList $arguments -WindowStyle Hidden -PassThru -Wait
    if ($extract.ExitCode -ne 0) { throw 'Administrative package extraction failed.' }
    $exe = Get-ChildItem -LiteralPath $native -Filter FreeSwitchConsole.exe -Recurse | Select-Object -First 1
}
$pidFile = Join-Path $integrationRoot 'fs.pid'
if (Test-Path -LiteralPath $pidFile) {
    $old = Get-Process -Id ([int](Get-Content -LiteralPath $pidFile)) -ErrorAction SilentlyContinue
    if ($old -and $old.Path -eq $exe.FullName) { Write-Output 'Isolated FreeSWITCH is already running.'; exit 0 }
}
foreach ($name in @('fs-logs', 'fs-db', 'fs-run')) { New-Item -ItemType Directory -Force -Path (Join-Path $AsciiJunction $name) | Out-Null }
$arguments = '-c -nonat -lp -base "' + $exe.DirectoryName + '" -conf "' + (Join-Path $AsciiJunction 'freeswitch') + '" -log "' + (Join-Path $AsciiJunction 'fs-logs') + '" -db "' + (Join-Path $AsciiJunction 'fs-db') + '" -run "' + (Join-Path $AsciiJunction 'fs-run') + '"'
$process = Start-Process $exe.FullName -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $integrationRoot 'fs.stdout.log') -RedirectStandardError (Join-Path $integrationRoot 'fs.stderr.log')
$process.Id | Set-Content -LiteralPath $pidFile
Write-Output "Isolated FreeSWITCH started as process $($process.Id); ESL 127.0.0.1:18021, SIP 127.0.0.1:15960."
