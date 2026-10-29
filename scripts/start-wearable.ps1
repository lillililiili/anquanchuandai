#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$SkipAndroid,
    [ValidatePattern('^emulator-[0-9]+$')]
    [string]$DeviceId = 'emulator-5554'
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$localDev = Join-Path $projectRoot '后端代码/melhat_server-dev/local-dev'
$runtimeRoot = Join-Path $projectRoot 'output/runtime'
$stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmssZ') + '-' + $PID
$results = [System.Collections.Generic.List[object]]::new()
$step = 'preflight'
$logDirectory = $null

function Add-Result([string]$Name, [string]$State, [string]$Detail) {
    $results.Add([pscustomobject]@{ service = $Name; state = $State; detail = $Detail })
}
function Require-File([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing required file: $Label" }
}
function Quote-Argument([string]$Value) {
    if ($Value.Contains('"') -or $Value.Contains("`r") -or $Value.Contains("`n")) { throw 'Unsupported character in a process argument.' }
    return '"' + $Value + '"'
}
function Same-Path([string]$Left, [string]$Right) {
    return $Left.Replace('\', '/').TrimEnd('/') -ieq $Right.Replace('\', '/').TrimEnd('/')
}
function Test-NodeCommand($Process, $Service, [string]$NodePath) {
    if (-not $Process -or -not (Same-Path $Process.ExecutablePath $NodePath) -or -not $Process.CommandLine) { return $false }
    $words = @([regex]::Matches($Process.CommandLine, '"[^"]*"|\S+') | ForEach-Object { $_.Value.Trim('"') })
    if ($words.Count -lt 2 -or -not (Same-Path $words[0] $NodePath)) { return $false }
    if ($Service.kind -eq 'gateway') { return $words.Count -eq 2 -and (Same-Path $words[1] $Service.script) }
    if (-not (Same-Path $words[1] $Service.script) -and $words[1].Replace('\','/') -ine 'node_modules/vite/bin/vite.js') { return $false }
    $offset = 2
    if ($words.Count -gt 2 -and (Same-Path $words[2] $Service.root)) { $offset = 3 }
    $arguments = @($words | Select-Object -Skip $offset) -join ' '
    $expected = '--host 127.0.0.1 --port ' + $Service.port
    return $arguments -eq $expected -or $arguments -eq ($expected + ' --strictPort')
}
function Get-LocalText([string]$Url) {
    if ($Url -notmatch '^http://127\.0\.0\.1:[0-9]+/') { throw 'Health checks must stay on loopback.' }
    Add-Type -AssemblyName System.Net.Http
    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.UseProxy = $false
    $handler.AllowAutoRedirect = $false
    $client = New-Object System.Net.Http.HttpClient($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(5)
    try { return $client.GetStringAsync($Url).GetAwaiter().GetResult() }
    finally { $client.Dispose(); $handler.Dispose() }
}
function Test-ViteSource([string]$Module, [string]$Source) {
    $identity = '\[\s*[''"]__file[''"]\s*,\s*[''"]' + [regex]::Escape($Source.Replace('\','/')) + '[''"]\s*\]'
    return $Module -match $identity
}
function Get-OwnedListener($Service) {
    $listeners = @(Get-NetTCPConnection -State Listen -ErrorAction Stop | Where-Object LocalPort -EQ $Service.port)
    if ($listeners.Count -eq 0) { return $null }
    if ($listeners.Count -ne 1 -or $listeners[0].LocalAddress -ne '127.0.0.1') { throw ('Port conflict: ' + $Service.port + '; no process was stopped.') }
    $process = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $listeners[0].OwningProcess)
    if (-not (Test-NodeCommand $process $Service $nodeExe)) { throw ('Process identity conflict on port ' + $Service.port + '; no process was stopped.') }
    if ($Service.kind -eq 'vite') {
        # Old launches used a relative CLI path. Confirm the served SFC's absolute
        # source identity as well, rather than accepting another project's Vite.
        $module = Get-LocalText ('http://127.0.0.1:' + $Service.port + $Service.probe)
        $source = (Join-Path $Service.root $Service.source).Replace('\','/')
        if (-not (Test-ViteSource $module $source)) { throw ('Vite source identity conflict on port ' + $Service.port + '; no process was stopped.') }
    }
    return $process
}
function Get-TunnelStatus($Service) {
    $control = Join-Path $Service.root 'cloud/tunnel.ps1'
    $local = Join-Path $Service.root '.local'
    $state = Join-Path $local ($Service.prefix + '-tunnel-process.json')
    $lock = Join-Path $local ($Service.prefix + '-tunnel-control.lock')
    # The existing Status command opens its lock with OpenOrCreate. Avoid even
    # that file creation in CheckOnly when this tunnel has never been started.
    if ($CheckOnly -and -not (Test-Path -LiteralPath $lock)) {
        if (Test-Path -LiteralPath $state) { throw ('Tunnel state has no existing control lock: ' + $Service.name) }
        return $null
    }
    $status = @(& $control -Action Status | Where-Object { $_ -isnot [string] })
    if ($status.Count -gt 1) { throw ('Unexpected tunnel status: ' + $Service.name) }
    if ($status.Count -eq 0) { return $null }
    return $status[0]
}
function Start-NodeService($Service) {
    $running = Get-OwnedListener $Service
    if ($running) { Add-Result $Service.name 'reused' ('PID ' + $running.ProcessId + ', port ' + $Service.port); return }
    $arguments = @(Quote-Argument $Service.script)
    if ($Service.kind -eq 'vite') {
        $arguments += @(Quote-Argument $Service.root) + @('--host', '127.0.0.1', '--port', [string]$Service.port, '--strictPort')
    }
    $started = Start-Process -FilePath $nodeExe -ArgumentList $arguments -WorkingDirectory $Service.root -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $logDirectory ($Service.name + '.out.log')) `
        -RedirectStandardError (Join-Path $logDirectory ($Service.name + '.err.log'))
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    do {
        Start-Sleep -Milliseconds 500
        if ($started.HasExited) { throw ('New process exited: ' + $Service.name + '; see runtime log.') }
        $running = Get-OwnedListener $Service
    } until ($running -or [DateTime]::UtcNow -ge $deadline)
    if (-not $running -or $running.ProcessId -ne $started.Id) { throw ('New process did not acquire its expected port: ' + $Service.name) }
    if ($Service.kind -eq 'gateway') {
        $statePath = Join-Path $Service.root '.local/gateway-process.json'
        if (Test-Path -LiteralPath $statePath) { Copy-Item -LiteralPath $statePath -Destination ($statePath + '.before-' + $stamp) }
        # Preserve the existing gateway state format used by recovery tooling.
        [ordered]@{ pid = $started.Id; startedUtc = $running.CreationDate.ToUniversalTime().ToString('o');
            script = $Service.script; host = '127.0.0.1'; port = $Service.port } |
            ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding utf8
    }
    Add-Result $Service.name 'started' ('PID ' + $started.Id + ', port ' + $Service.port)
}

try {
    # Existing tunnel journals contain UTF-8 paths without a BOM. Their original
    # controllers must run in PowerShell 7 (5.1's default ANSI reader corrupts
    # those paths), rather than rewriting state/fingerprints to suit the shell.
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        $command = Get-Command pwsh.exe -ErrorAction SilentlyContinue
        $candidates = @($(if ($command) { $command.Source }),
            (Join-Path $env:ProgramFiles 'PowerShell/7/pwsh.exe'),
            (Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe'))
        $shell7 = $null
        foreach ($candidate in $candidates) {
            if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
                $major = & $candidate -NoLogo -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.Major' 2>$null
                if ($LASTEXITCODE -eq 0 -and [string]$major -match '^[7-9][0-9]*$') { $shell7 = $candidate; break }
            }
        }
        if (-not $shell7) { throw 'PowerShell 7 is required to read the existing tunnel state; run this script from an installed PowerShell 7.' }
        $launchArgs = @('-NoLogo','-NoProfile','-NonInteractive','-File',$PSCommandPath,'-DeviceId',$DeviceId)
        if ($CheckOnly) { $launchArgs += '-CheckOnly' }
        if ($SkipAndroid) { $launchArgs += '-SkipAndroid' }
        & $shell7 @launchArgs
        exit $LASTEXITCODE
    }
    $nodeExe = (Get-Command node.exe -ErrorAction Stop).Source
    $dockerExe = (Get-Command docker.exe -ErrorAction Stop).Source
    $services = @(
        @{ name='portal'; kind='vite'; port=5191; root=(Join-Path $projectRoot 'pc前台项目'); probe='/src/App.vue'; source='src/App.vue' },
        @{ name='admin'; kind='vite'; port=5181; root=(Join-Path $projectRoot 'pc后台项目'); probe='/App.vue'; source='App.vue' },
        @{ name='helmet-gateway'; kind='gateway'; port=18086; root=(Join-Path $localDev 'device-gateway'); prefix='helmet' },
        @{ name='belt-gateway'; kind='gateway'; port=18087; root=(Join-Path $localDev 'belt-device-gateway'); prefix='belt' }
    )
    foreach ($service in $services) {
        $step = $service.name + ' preflight'
        $service.script = Join-Path $service.root $(if ($service.kind -eq 'vite') { 'node_modules/vite/bin/vite.js' } else { 'cli.mjs' })
        Require-File $service.script ($service.name + ' entry point')
        if ($service.kind -eq 'gateway') {
            Require-File (Join-Path $service.root '.local/config.json') ($service.name + ' existing configuration')
            Require-File (Join-Path $service.root 'cloud/tunnel.ps1') ($service.name + ' tunnel controller')
            Require-File (Join-Path $service.root ('.local/' + $service.prefix + '_tunnel_ed25519')) ($service.name + ' existing SSH key')
            Require-File (Join-Path $service.root '.local/known_hosts') ($service.name + ' existing known_hosts')
            $null = & $nodeExe $service.script --check 2>&1
            if ($LASTEXITCODE -ne 0) { throw ('Configuration check failed: ' + $service.name + '; no configuration was changed.') }
            $config = Get-Content -LiteralPath (Join-Path $service.root '.local/config.json') -Raw | ConvertFrom-Json
            if ($config.listenHost -ne '127.0.0.1' -or $config.listenPort -ne $service.port -or $config.upstreamOrigin -ne 'http://127.0.0.1:18084') { throw ('Unexpected loopback endpoint: ' + $service.name) }
            $config = $null
        }
        $service.running = Get-OwnedListener $service
    }
    Require-File (Join-Path $env:WINDIR 'System32/OpenSSH/ssh.exe') 'existing Windows SSH client'
    $containers = @()
    foreach ($name in @('melhat-mysql','melhat-redis','melhat-backend')) {
        $step = $name + ' preflight'
        $state = @(& $dockerExe inspect --type container --format '{{.Name}}|{{.State.Status}}|{{.State.Running}}' $name 2>$null)
        if ($LASTEXITCODE -ne 0 -or $state.Count -ne 1) { throw ('Existing container unavailable: ' + $name + '; start Docker Desktop and check the daily installation.') }
        $parts = ([string]$state[0]).Split('|')
        if ($parts.Count -ne 3 -or $parts[0] -cne ('/' + $name)) { throw ('Unexpected container identity: ' + $name) }
        $containers += @{ name=$name; running=($parts[2] -eq 'true'); status=$parts[1] }
    }
    foreach ($service in @($services | Where-Object kind -EQ 'gateway')) { $step = $service.prefix + '-tunnel preflight'; $service.tunnel = Get-TunnelStatus $service }
    if (-not $SkipAndroid) {
        $step = 'android preflight'
        $adbCandidate = if ($env:ANDROID_DEV_HOME) { Join-Path $env:ANDROID_DEV_HOME 'android-sdk/platform-tools/adb.exe' } else { 'D:/AndroidDev/android-sdk/platform-tools/adb.exe' }
        $adbExe = if (Test-Path -LiteralPath $adbCandidate) { $adbCandidate } else { (Get-Command adb.exe -ErrorAction Stop).Source }
        if ($CheckOnly -and -not (Get-NetTCPConnection -State Listen -LocalPort 5037 -ErrorAction SilentlyContinue)) { throw 'ADB is not running; CheckOnly will not start it. Start the emulator or use -SkipAndroid.' }
        $devices = @(& $adbExe devices 2>$null)
        if ($LASTEXITCODE -ne 0 -or -not ($devices -match ('^' + [regex]::Escape($DeviceId) + '\s+device\s*$'))) { throw 'Selected emulator is unavailable; open it or use -SkipAndroid.' }
        $installed = @(& $adbExe -s $DeviceId shell pm path com.rolling.intelligence_headband 2>$null)
        if ($LASTEXITCODE -ne 0 -or -not ($installed -match '^package:')) { throw 'The wearable app is not installed on the selected emulator; no installation or data reset was attempted.' }
    }
    if ($CheckOnly) {
        foreach ($container in $containers) { Add-Result $container.name $(if ($container.running) {'running'} else {'stopped'}) $container.status }
        foreach ($service in $services) { Add-Result $service.name $(if ($service.running) {'running'} else {'stopped'}) ('port ' + $service.port) }
    } else {
        $logDirectory = Join-Path $runtimeRoot ('start-wearable-' + $stamp)
        New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
        foreach ($container in $containers) {
            $step = $container.name
            if (-not $container.running) {
                $null = & $dockerExe start $container.name 2>&1
                if ($LASTEXITCODE -ne 0) { throw ('Could not start existing container: ' + $container.name) }
            }
            Add-Result $container.name $(if ($container.running) {'reused'} else {'started'}) 'Existing daily container; configuration retained.'
        }
        $step = 'backend readiness'
        $deadline = [DateTime]::UtcNow.AddSeconds(45)
        $ready = $false
        do {
            try { $null = Get-LocalText 'http://127.0.0.1:18084/'; $ready = $true } catch { Start-Sleep -Milliseconds 750 }
        } until ($ready -or [DateTime]::UtcNow -ge $deadline)
        if (-not $ready) { throw 'Backend did not respond within 45 seconds; existing containers were retained.' }
        foreach ($service in $services) { $step = $service.name; Start-NodeService $service }
    }
    foreach ($service in @($services | Where-Object kind -EQ 'gateway')) {
        $step = $service.prefix + '-tunnel'
        $status = $service.tunnel
        if (-not $CheckOnly) {
            $null = & (Join-Path $service.root 'cloud/tunnel.ps1') -Action Start
            $deadline = [DateTime]::UtcNow.AddSeconds(15)
            do { $status = Get-TunnelStatus $service; if ($status -and $status.sshAlive) { break }; Start-Sleep -Milliseconds 500 } while ([DateTime]::UtcNow -lt $deadline)
        }
        $state = if ($status -and $status.workerAlive -and $status.sshAlive) {'running'} elseif ($status -and $status.workerAlive) {'reconnecting'} else {'stopped'}
        Add-Result $step $state $(if ($status) { [string]$status.status } else { 'No active owned tunnel.' })
    }
    if (-not $SkipAndroid) {
        $step = 'android'
        if (-not $CheckOnly) {
            $null = & $adbExe -s $DeviceId reverse tcp:18084 tcp:18084 2>&1
            if ($LASTEXITCODE -ne 0) { throw 'Android backend forwarding failed.' }
            $launch = @(& $adbExe -s $DeviceId shell am start -W -n com.rolling.intelligence_headband/.MainActivity 2>&1)
            if ($LASTEXITCODE -ne 0 -or -not ($launch -match '^Status: ok')) { throw 'Android app could not be opened; app data was preserved.' }
        }
        $forward = @(& $adbExe -s $DeviceId reverse --list 2>$null)
        $appPid = @(& $adbExe -s $DeviceId shell pidof com.rolling.intelligence_headband 2>$null)
        $active = ($appPid -match '^\d+( \d+)*$') -and ($forward -match 'tcp:18084\s+tcp:18084$')
        Add-Result 'android' $(if ($active) {'running'} else {'stopped'}) ('Installed app on ' + $DeviceId + '; backend forwarding ' + [bool]($forward -match 'tcp:18084\s+tcp:18084$'))
    }
    $incomplete = @($results | Where-Object { $_.state -in @('stopped','reconnecting') }).Count -gt 0
    $report = [ordered]@{ checkedAtUtc=[DateTime]::UtcNow.ToString('o'); checkOnly=[bool]$CheckOnly; ready=(-not $incomplete); androidSkipped=[bool]$SkipAndroid; services=@($results.ToArray()) }
    $json = $report | ConvertTo-Json -Depth 5
    if ($logDirectory) { $json | Set-Content -LiteralPath (Join-Path $logDirectory 'summary.json') -Encoding utf8 }
    Write-Output $json
    if ($incomplete) { exit 1 }
} catch {
    # External command output/configuration never enters the summary or console.
    $message = if ($_.Exception.Message -match '^(PowerShell 7 is required|Missing required file:|Unsupported character|Health checks|Port conflict:|Process identity conflict|Vite source identity conflict|Tunnel state has|Unexpected tunnel|New process|Configuration check failed:|Unexpected loopback endpoint:|Existing container unavailable:|Unexpected container identity:|ADB is not running|Selected emulator|The wearable app|Could not start existing container:|Backend did not respond|Android backend|Android app)') { $_.Exception.Message } else { 'Operation failed during ' + $step + '; check local permissions, Docker, and the existing service logs. No conflicting process was stopped.' }
    Add-Result $step 'error' $message
    $json = [ordered]@{ checkedAtUtc=[DateTime]::UtcNow.ToString('o'); checkOnly=[bool]$CheckOnly; ready=$false; errorType=$_.Exception.GetType().Name; scriptLine=$_.InvocationInfo.ScriptLineNumber; services=@($results.ToArray()) } | ConvertTo-Json -Depth 5
    if ($logDirectory) { $json | Set-Content -LiteralPath (Join-Path $logDirectory 'summary.json') -Encoding utf8 }
    Write-Output $json
    exit 1
}
