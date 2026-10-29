[CmdletBinding()]
param(
    [ValidateSet('Start', 'Stop', 'Status', 'Worker')]
    [string]$Action = 'Status',
    [string]$Instance = ''
)

$ErrorActionPreference = 'Stop'
$gatewayDirectory = Split-Path -Parent $PSScriptRoot
$localDirectory = Join-Path $gatewayDirectory '.local'
$stateFile = Join-Path $localDirectory 'wear-api-tunnel-process.json'
$lockFile = Join-Path $localDirectory 'wear-api-tunnel-control.lock'
$scriptFile = $PSCommandPath
$sshExecutable = Join-Path $env:WINDIR 'System32/OpenSSH/ssh.exe'
$keyFile = Join-Path $localDirectory 'wear_api_tunnel_ed25519'
$knownHostsFile = Join-Path $localDirectory 'known_hosts'
$forward = '10.255.1.1:28088:127.0.0.1:18088'
$destination = 'wear-api-tunnel@39.106.212.138'
$maximumConsecutiveFailures = 12
$stableRunSeconds = 60
$retryDelaySeconds = 10

function Get-RetryDecision([int]$ConsecutiveFailures, [double]$RunSeconds,
    [bool]$StopRequested, [int]$MaximumFailures = 12, [int]$StableSeconds = 60) {
    if ($StopRequested) {
        return [pscustomobject]@{ consecutiveFailures = $ConsecutiveFailures; retry = $false; status = 'stopped' }
    }
    $failures = $(if ($RunSeconds -ge $StableSeconds) { 0 } else { $ConsecutiveFailures + 1 })
    return [pscustomobject]@{ consecutiveFailures = $failures; retry = ($failures -lt $MaximumFailures);
        status = $(if ($failures -ge $MaximumFailures) { 'retry-limit-reached' } else { 'waiting-to-reconnect' }) }
}

function Get-ExitCategory($ExitCode, [bool]$StopRequested, [string]$ErrorLogPath) {
    if ($StopRequested) { return 'requested-stop' }
    if ($null -eq $ExitCode) { return 'exit-unknown' }
    if ($ExitCode -eq 0) { return 'clean-exit' }
    # Inspect the existing short tail only; persist the enum, never its contents.
    try { $tail = (Get-Content -LiteralPath $ErrorLogPath -Tail 12 -ErrorAction Stop) -join "`n" }
    catch { return 'ssh-error' }
    if ($tail -match 'Host key verification failed|REMOTE HOST IDENTIFICATION HAS CHANGED') { return 'host-key-failed' }
    if ($tail -match 'Permission denied|Authentication failed|No more authentication methods') { return 'authentication-failed' }
    if ($tail -match 'remote port forwarding failed|remote forward failure|cannot listen to port') { return 'forward-rejected' }
    if ($tail -match 'Connection timed out|Operation timed out|Connection refused|Connection reset|Connection closed|Broken pipe|No route to host|Network is unreachable|not responding|Could not resolve hostname') { return 'network-error' }
    return 'ssh-error'
}

function Enter-ControlLock {
    for ($attempt = 0; $attempt -lt 50; $attempt++) {
        try {
            return [System.IO.File]::Open($lockFile, [System.IO.FileMode]::OpenOrCreate,
                [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        } catch [System.IO.IOException] { Start-Sleep -Milliseconds 100 }
    }
    throw 'Another tunnel control operation is still in progress.'
}

function Read-State {
    if (-not (Test-Path -LiteralPath $stateFile)) { return $null }
    return (Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json)
}

function Write-State($State) {
    # All readers/writers hold the same exclusive lock.
    [System.IO.File]::WriteAllText($stateFile, ($State | ConvertTo-Json -Depth 8),
        (New-Object System.Text.UTF8Encoding($false)))
}

function Get-Fingerprint([int]$ProcessId) {
    $process = Get-CimInstance Win32_Process -Filter ('ProcessId = ' + $ProcessId)
    if ($null -eq $process) { return $null }
    return [pscustomobject]@{
        pid = [int]$process.ProcessId
        parentPid = [int]$process.ParentProcessId
        createdUtc = $process.CreationDate.ToUniversalTime().ToString('o')
        executable = [string]$process.ExecutablePath
        commandLine = [string]$process.CommandLine
    }
}

function Match-Fingerprint($Expected) {
    if ($null -eq $Expected) { return $false }
    $actual = Get-Fingerprint ([int]$Expected.pid)
    if ($null -eq $actual) { return $false }
    $actualTicks = ([datetime]$actual.createdUtc).ToUniversalTime().Ticks
    $expectedTicks = ([datetime]$Expected.createdUtc).ToUniversalTime().Ticks
    return ($actualTicks -eq $expectedTicks -and
        $actual.parentPid -eq $Expected.parentPid -and
        $actual.executable -eq $Expected.executable -and
        $actual.commandLine -ceq $Expected.commandLine)
}

function Assert-WorkerRecord($State) {
    if ($null -eq $State -or $State.script -ne $scriptFile -or
        $State.instance -notmatch '^[0-9a-f]{32}$' -or $null -eq $State.worker -or
        $State.worker.commandLine.IndexOf($scriptFile, [StringComparison]::OrdinalIgnoreCase) -lt 0 -or
        $State.worker.commandLine.IndexOf($State.instance, [StringComparison]::Ordinal) -lt 0) {
        throw 'The state file does not describe a worker created by this script.'
    }
}

function Stop-OwnedChild($State) {
    if ($null -eq $State.child) { return }
    $actual = Get-Fingerprint ([int]$State.child.pid)
    if ($null -eq $actual) { return }
    if ($State.child.parentPid -ne $State.worker.pid -or
        $State.child.executable -ne $sshExecutable -or
        $State.child.commandLine.IndexOf($forward, [StringComparison]::Ordinal) -lt 0 -or
        $State.child.commandLine.IndexOf($destination, [StringComparison]::Ordinal) -lt 0 -or
        -not (Match-Fingerprint $State.child)) {
        throw 'SSH process ownership could not be verified; no process was stopped.'
    }
    Stop-Process -Id ([int]$State.child.pid) -ErrorAction Stop
}

function Quote-NativeArgument([string]$Value) {
    if ($Value.Contains('"')) { throw 'Unexpected quote in a fixed process argument.' }
    return '"' + $Value + '"'
}

if (-not (Test-Path -LiteralPath $localDirectory -PathType Container)) {
    throw 'Existing gateway .local configuration directory was not found.'
}

if ($Action -eq 'Start') {
    $control = Enter-ControlLock
    try {
        $state = Read-State
        if ($null -ne $state) {
            Assert-WorkerRecord $state
            if (Match-Fingerprint $state.worker) {
                Write-Output ('Already running: worker PID ' + $state.worker.pid + '; status ' + $state.status)
                return
            }
            if ($null -ne $state.child -and (Match-Fingerprint $state.child)) {
                throw 'A child from the previous run is still alive; use Stop before starting again.'
            }
        }
        foreach ($requiredFile in @($sshExecutable, $keyFile, $knownHostsFile)) {
            if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) { throw 'A required SSH executable, key or known_hosts file is missing.' }
        }
        $existing = @(Get-CimInstance Win32_Process -Filter "Name = 'ssh.exe'" | Where-Object {
            $_.CommandLine -and $_.CommandLine.Contains($forward) -and $_.CommandLine.Contains($destination)
        })
        if ($existing.Count -gt 0) { throw 'An existing SSH process already uses this forwarding destination. Leave it alone or stop that original session before using Start.' }
        $probe = New-Object System.Net.Sockets.TcpClient
        try {
            $pending = $probe.ConnectAsync('127.0.0.1', 18088)
            if (-not $pending.Wait(1500) -or -not $probe.Connected) { throw 'The existing loopback gateway is not listening on port 18088.' }
        } finally { $probe.Dispose() }
        $instanceId = [Guid]::NewGuid().ToString('N')
        $shellExecutable = (Get-Process -Id $PID).Path
        $arguments = @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $scriptFile,
            '-Action', 'Worker', '-Instance', $instanceId) | ForEach-Object { Quote-NativeArgument $_ }
        $worker = Start-Process -FilePath $shellExecutable -ArgumentList $arguments -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput (Join-Path $localDirectory 'wear-api-tunnel-worker.out.log') `
            -RedirectStandardError (Join-Path $localDirectory 'wear-api-tunnel-worker.err.log')
        $fingerprint = Get-Fingerprint $worker.Id
        if ($null -eq $fingerprint) { throw 'The hidden worker exited before initialization.' }
        $state = [pscustomobject]@{ version = 2; script = $scriptFile; instance = $instanceId;
            worker = $fingerprint; child = $null; stopRequested = $false; status = 'starting';
            attempts = 0; totalAttempts = 0; consecutiveFailures = 0;
            lastExitCode = $null; lastExitAtUtc = $null; lastExitCategory = $null;
            lastRunSeconds = $null; lastStableAtUtc = $null }
        Write-State $state
        Write-Output ('Started hidden tunnel worker PID ' + $worker.Id + '. Use Status to inspect it.')
    } finally { $control.Dispose() }
    return
}

if ($Action -eq 'Status') {
    $control = Enter-ControlLock
    try {
        $state = Read-State
        if ($null -eq $state) { Write-Output 'No tunnel has been started by this script.'; return }
        Assert-WorkerRecord $state
        [pscustomobject]@{ status = $state.status; workerPid = $state.worker.pid;
            workerAlive = (Match-Fingerprint $state.worker); sshPid = $(if ($state.child) { $state.child.pid } else { $null });
            sshAlive = (Match-Fingerprint $state.child); attempts = $state.attempts;
            totalAttempts = $(if ($null -ne $state.totalAttempts) { $state.totalAttempts } else { $state.attempts });
            consecutiveFailures = $state.consecutiveFailures; lastExitCode = $state.lastExitCode;
            lastExitAtUtc = $state.lastExitAtUtc; lastExitCategory = $state.lastExitCategory;
            lastRunSeconds = $state.lastRunSeconds; lastStableAtUtc = $state.lastStableAtUtc }
    } finally { $control.Dispose() }
    return
}

if ($Action -eq 'Stop') {
    $control = Enter-ControlLock
    try {
        $state = Read-State
        if ($null -eq $state) { Write-Output 'No recorded tunnel to stop.'; return }
        Assert-WorkerRecord $state
        $state.stopRequested = $true
        Write-State $state
        Stop-OwnedChild $state
        $workerIdentity = $state.worker
    } finally { $control.Dispose() }
    for ($attempt = 0; $attempt -lt 16; $attempt++) {
        if (-not (Match-Fingerprint $workerIdentity)) { break }
        Start-Sleep -Milliseconds 500
    }
    $control = Enter-ControlLock
    try {
        $state = Read-State
        Assert-WorkerRecord $state
        if (([datetime]$state.worker.createdUtc).ToUniversalTime().Ticks -ne
            ([datetime]$workerIdentity.createdUtc).ToUniversalTime().Ticks -or $state.worker.pid -ne $workerIdentity.pid) {
            throw 'The recorded worker changed during Stop; leaving the newer run untouched.'
        }
        Stop-OwnedChild $state
        if (Match-Fingerprint $workerIdentity) { Stop-Process -Id ([int]$workerIdentity.pid) -ErrorAction Stop }
        $state.status = 'stopped'
        $state.child = $null
        Write-State $state
        Write-Output 'Stopped only this script-owned tunnel. The gateway and backend were left running.'
    } finally { $control.Dispose() }
    return
}

# Internal hidden worker. No scheduled task, service or automatic startup is installed.
if ($Instance -notmatch '^[0-9a-f]{32}$') { throw 'Worker requires a valid launch instance.' }
$sshProcess = $null
try {
    $retryRequired = $false
    while ($true) {
        if ($retryRequired) {
            for ($tick = 0; $tick -lt ($retryDelaySeconds * 2); $tick++) {
                Start-Sleep -Milliseconds 500
                $control = Enter-ControlLock
                try { $state = Read-State; if ($state.instance -ne $Instance -or $state.stopRequested) { return } }
                finally { $control.Dispose() }
            }
        }
        $control = Enter-ControlLock
        try {
            $state = Read-State
            Assert-WorkerRecord $state
            if ($state.instance -ne $Instance -or $state.worker.pid -ne $PID -or $state.stopRequested) { return }
            $sshArguments = @('-F', 'NUL', '-N', '-T', '-a', '-x', '-p', '22', '-i', $keyFile,
                '-o', 'IdentitiesOnly=yes', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes',
                '-o', 'GlobalKnownHostsFile=NUL', '-o', 'ControlMaster=no', '-o', 'ControlPath=none',
                '-o', ('UserKnownHostsFile=' + $knownHostsFile), '-o', 'ExitOnForwardFailure=yes',
                '-o', 'ConnectTimeout=10', '-o', 'ServerAliveInterval=30', '-o', 'ServerAliveCountMax=3',
                '-R', $forward, $destination) | ForEach-Object { Quote-NativeArgument $_ }
            $sshProcess = $null
            try {
                $stableObserved = $false
                $state.totalAttempts = [long]$state.totalAttempts + 1
                $state.attempts = $state.totalAttempts
                $sshProcess = Start-Process -FilePath $sshExecutable -ArgumentList $sshArguments -WindowStyle Hidden -PassThru `
                    -RedirectStandardOutput (Join-Path $localDirectory 'wear-api-tunnel-ssh.out.log') `
                    -RedirectStandardError (Join-Path $localDirectory 'wear-api-tunnel-ssh.err.log')
                $runTimer = [System.Diagnostics.Stopwatch]::StartNew()
                # Keep this newly created process object for cleanup if recording fails.
                $null = $sshProcess.Handle
                $state.child = Get-Fingerprint $sshProcess.Id
                $state.status = 'ssh-running'
                Write-State $state
            } catch {
                if ($null -ne $sshProcess -and -not $sshProcess.HasExited) {
                    $sshProcess.Kill()
                    $null = $sshProcess.WaitForExit(2000)
                }
                $state.lastExitCode = $null
                $state.lastExitAtUtc = [datetime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss'Z'")
                $state.lastExitCategory = $(if ($null -eq $sshProcess) { 'launch-failed' } else { 'worker-error' })
                try { Write-State $state } catch { }
                throw 'The tunnel worker could not start or record its owned SSH process.'
            }
        } finally { $control.Dispose() }
        while (-not $sshProcess.WaitForExit(500)) {
            $control = Enter-ControlLock
            try {
                $state = Read-State
                if ($state.instance -ne $Instance -or $state.worker.pid -ne $PID) { return }
                if ($state.stopRequested) { Stop-OwnedChild $state }
                elseif (-not $stableObserved -and -not $sshProcess.HasExited -and $runTimer.Elapsed.TotalSeconds -ge $stableRunSeconds) {
                    # This budget reset means process survival, not device/business health.
                    $stableObserved = $true
                    $state.consecutiveFailures = 0
                    $state.lastStableAtUtc = [datetime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss'Z'")
                    Write-State $state
                }
            } finally { $control.Dispose() }
        }
        $runTimer.Stop()
        $control = Enter-ControlLock
        try {
            $state = Read-State
            if ($state.instance -ne $Instance -or $state.worker.pid -ne $PID) { return }
            $exitCode = $null
            try {
                $sshProcess.Refresh()
                if ($null -ne $sshProcess.ExitCode) { $exitCode = [int]$sshProcess.ExitCode }
            } catch { }
            $state.lastExitCode = $exitCode
            $state.lastExitAtUtc = [datetime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss'Z'")
            $state.lastExitCategory = Get-ExitCategory $exitCode $state.stopRequested (Join-Path $localDirectory 'wear-api-tunnel-ssh.err.log')
            $state.lastRunSeconds = [math]::Floor($runTimer.Elapsed.TotalSeconds)
            $decision = Get-RetryDecision $state.consecutiveFailures $runTimer.Elapsed.TotalSeconds `
                $state.stopRequested $maximumConsecutiveFailures $stableRunSeconds
            $state.consecutiveFailures = $decision.consecutiveFailures
            $state.child = $null
            $state.status = $decision.status
            Write-State $state
        } finally { $control.Dispose() }
        if (-not $decision.retry) { break }
        $retryRequired = $true
    }
} finally {
    $control = Enter-ControlLock
    try {
        $state = Read-State
        if ($null -ne $state -and $state.instance -eq $Instance -and $state.worker.pid -eq $PID) {
            Stop-OwnedChild $state
            $state.child = $null
            if ($state.stopRequested) { $state.status = 'stopped' }
            elseif ($state.status -ne 'retry-limit-reached') { $state.status = 'ended-check-ssh-log' }
            Write-State $state
        }
    } finally { $control.Dispose() }
}
