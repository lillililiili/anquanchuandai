[CmdletBinding()]
param(
    [ValidateSet('Start', 'Stop', 'Status', 'Worker')]
    [string]$Action = 'Status',
    [string]$Instance = ''
)

$ErrorActionPreference = 'Stop'
$gatewayDirectory = Split-Path -Parent $PSScriptRoot
$localDirectory = Join-Path $gatewayDirectory '.local'
$stateFile = Join-Path $localDirectory 'belt-tunnel-process.json'
$lockFile = Join-Path $localDirectory 'belt-tunnel-control.lock'
$scriptFile = $PSCommandPath
$sshExecutable = Join-Path $env:WINDIR 'System32/OpenSSH/ssh.exe'
$keyFile = Join-Path $localDirectory 'belt_tunnel_ed25519'
$knownHostsFile = Join-Path $localDirectory 'known_hosts'
$forward = '10.255.1.1:28087:127.0.0.1:18087'
$destination = 'belt-tunnel@39.106.212.138'
$maximumConsecutiveShortFailures = 31
$retryDelaySeconds = 10
$stableConnectionSeconds = 120
$eventFile = Join-Path $localDirectory 'belt-tunnel-events.jsonl'
$maximumEventFileBytes = 131072
$eventArchiveCount = 2
$stateReplaceAttempts = 20
$stateReplaceDelayMilliseconds = 100

function Get-RetryOutcome([int]$ConsecutiveShortFailures, [double]$AliveSeconds,
    [int]$ExitCode, [bool]$StopRequested = $false) {
    $stable = $AliveSeconds -ge $stableConnectionSeconds
    $failures = $(if ($stable) { 0 } else { $ConsecutiveShortFailures + 1 })
    $category = if ($StopRequested) { 'operator-stop' }
        elseif ($stable) { 'stable-session-ended' }
        elseif ($ExitCode -eq 0) { 'short-clean-exit' }
        else { 'short-ssh-failure' }
    return [pscustomobject]@{ consecutiveShortFailures = $failures;
        shouldRetry = (-not $StopRequested -and $failures -lt $maximumConsecutiveShortFailures);
        category = $category }
}

function Write-TunnelEvent(
    [ValidateSet('attempt-started', 'connection-stable', 'attempt-exited', 'retry-budget-exhausted', 'worker-ended')]
    [string]$Event,
    [ValidateSet('none', 'operator-stop', 'stable-session-ended', 'short-clean-exit', 'short-ssh-failure', 'retry-budget-exhausted', 'worker-error')]
    [string]$Category,
    [ValidateRange(0, [double]::MaxValue)][double]$AliveSeconds = 0,
    [Nullable[int]]$ExitCode = $null,
    [long]$TotalAttempts = 0,
    [int]$ConsecutiveShortFailures = 0
) {
    # Callers hold the control lock. Never accept raw SSH output, URLs, key paths,
    # exception text or caller-supplied fields in this small diagnostic journal.
    $record = [ordered]@{ utc = [DateTime]::UtcNow.ToString('o'); event = $Event;
        aliveSeconds = [Math]::Round($AliveSeconds, 3); exitCode = $ExitCode;
        category = $Category; totalAttempts = $TotalAttempts;
        consecutiveShortFailures = $ConsecutiveShortFailures }
    $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes(($record | ConvertTo-Json -Compress) + "`n")
    if ($bytes.Length -gt $maximumEventFileBytes) { throw 'Tunnel event exceeds the fixed journal limit.' }
    if ([System.IO.File]::Exists($eventFile) -and
        (Get-Item -LiteralPath $eventFile).Length + $bytes.Length -gt $maximumEventFileBytes) {
        $oldest = $eventFile + '.' + $eventArchiveCount
        if ([System.IO.File]::Exists($oldest)) { [System.IO.File]::Delete($oldest) }
        for ($archive = $eventArchiveCount - 1; $archive -ge 1; $archive--) {
            $source = $eventFile + '.' + $archive
            if ([System.IO.File]::Exists($source)) { [System.IO.File]::Move($source, $eventFile + '.' + ($archive + 1)) }
        }
        [System.IO.File]::Move($eventFile, $eventFile + '.1')
    }
    $stream = [System.IO.File]::Open($eventFile, [System.IO.FileMode]::Append,
        [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
    try { $stream.Write($bytes, 0, $bytes.Length) }
    finally { $stream.Dispose() }
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
    return (Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Test-RetryableStateReplaceError([System.Exception]$Failure) {
    $cause = $Failure.GetBaseException()
    # Windows sharing/lock violations, or ReplaceFile's unable-to-remove error.
    # 1175 preserves both original names; 1176/1177 may partially rename files.
    return ($cause -is [System.IO.IOException] -and ($cause.HResult -band 0xffff) -in @(32, 33, 1175))
}

function Write-State($State) {
    # All readers/writers hold the same exclusive lock.
    $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes(($State | ConvertTo-Json -Depth 8))
    $temporary = Join-Path $localDirectory ('.belt-tunnel-state-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    $stream = $null
    try {
        $stream = [System.IO.File]::Open($temporary, [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
        $stream.Dispose()
        $stream = $null
        if ([System.IO.File]::Exists($stateFile)) {
            # Keep the same fully flushed temporary file and control lock. A
            # brief external reader must not kill a healthy SSH worker. Never
            # fall back to deleting/truncating state or weakening its ACLs.
            for ($replaceAttempt = 1; ; $replaceAttempt++) {
                try {
                    [System.IO.File]::Replace($temporary, $stateFile, [System.Management.Automation.Language.NullString]::Value)
                    break
                } catch {
                    if ($replaceAttempt -ge $stateReplaceAttempts -or
                        -not (Test-RetryableStateReplaceError $_.Exception)) { throw }
                    Start-Sleep -Milliseconds $stateReplaceDelayMilliseconds
                }
            }
        } else {
            [System.IO.File]::Move($temporary, $stateFile)
        }
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
        if ([System.IO.File]::Exists($temporary)) { [System.IO.File]::Delete($temporary) }
    }
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

function Complete-Worker($OwnedProcess) {
    # Only the Process returned by this worker's Start-Process is accepted here.
    # Its Handle is retained immediately after launch, so cleanup never reopens
    # a recorded PID that might have been reused. Do this before reading state:
    # an unreadable/changed journal must not leave our own SSH child alive.
    if ($null -ne $OwnedProcess) {
        try {
            if (-not $OwnedProcess.HasExited) {
                $OwnedProcess.Kill()
                if (-not $OwnedProcess.WaitForExit(2000)) {
                    throw 'The worker-owned SSH process did not stop.'
                }
            }
        } finally { $OwnedProcess.Dispose() }
    }
    $control = Enter-ControlLock
    try {
        $state = Read-State
        if ($null -ne $state -and $state.instance -eq $Instance -and $state.worker.pid -eq $PID) {
            $state.child = $null
            if ($null -ne $state.PSObject.Properties['connectionStable']) { $state.connectionStable = $false }
            $state.status = $(if ($state.stopRequested) { 'stopped' }
                elseif ($state.status -eq 'retry-budget-exhausted') { 'retry-budget-exhausted' }
                else { 'ended-check-ssh-log' })
            Write-State $state
            $endCategory = $(if ($state.stopRequested) { 'operator-stop' }
                elseif ($state.status -eq 'retry-budget-exhausted') { 'retry-budget-exhausted' }
                else { 'worker-error' })
            Write-TunnelEvent -Event 'worker-ended' -Category $endCategory `
                -TotalAttempts $state.totalAttempts -ConsecutiveShortFailures $state.consecutiveShortFailures
        }
    } finally { $control.Dispose() }
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
            $pending = $probe.ConnectAsync('127.0.0.1', 18087)
            if (-not $pending.Wait(1500) -or -not $probe.Connected) { throw 'The existing loopback gateway is not listening on port 18087.' }
        } finally { $probe.Dispose() }
        $instanceId = [Guid]::NewGuid().ToString('N')
        $shellExecutable = (Get-Process -Id $PID).Path
        $arguments = @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $scriptFile,
            '-Action', 'Worker', '-Instance', $instanceId) | ForEach-Object { Quote-NativeArgument $_ }
        $worker = Start-Process -FilePath $shellExecutable -ArgumentList $arguments -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput (Join-Path $localDirectory 'belt-tunnel-worker.out.log') `
            -RedirectStandardError (Join-Path $localDirectory 'belt-tunnel-worker.err.log')
        $fingerprint = Get-Fingerprint $worker.Id
        if ($null -eq $fingerprint) { throw 'The hidden worker exited before initialization.' }
        $state = [pscustomobject]@{ version = 2; script = $scriptFile; instance = $instanceId;
            worker = $fingerprint; child = $null; stopRequested = $false; status = 'starting';
            attempts = 0; totalAttempts = 0; consecutiveShortFailures = 0; connectionStable = $false }
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
            consecutiveShortFailures = $state.consecutiveShortFailures; connectionStable = $state.connectionStable }
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
$connectionClock = $null
$totalAttempts = 0L
$consecutiveShortFailures = 0
try {
    while ($true) {
        if ($totalAttempts -gt 0) {
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
                $sshProcess = Start-Process -FilePath $sshExecutable -ArgumentList $sshArguments -WindowStyle Hidden -PassThru `
                    -RedirectStandardOutput (Join-Path $localDirectory 'belt-tunnel-ssh.out.log') `
                    -RedirectStandardError (Join-Path $localDirectory 'belt-tunnel-ssh.err.log')
                # Keep this newly created process object for cleanup if recording fails.
                $null = $sshProcess.Handle
                $connectionClock = [System.Diagnostics.Stopwatch]::StartNew()
                $totalAttempts++
                $stableRecorded = $false
                $state.child = Get-Fingerprint $sshProcess.Id
                $state.status = 'ssh-running'
                $state.attempts = $totalAttempts
                $state.totalAttempts = $totalAttempts
                $state.consecutiveShortFailures = $consecutiveShortFailures
                $state.connectionStable = $false
                Write-State $state
                Write-TunnelEvent -Event 'attempt-started' -Category 'none' `
                    -TotalAttempts $totalAttempts -ConsecutiveShortFailures $consecutiveShortFailures
            } catch {
                if ($null -ne $sshProcess -and -not $sshProcess.HasExited) {
                    $sshProcess.Kill()
                    $null = $sshProcess.WaitForExit(2000)
                }
                throw
            }
        } finally { $control.Dispose() }
        while (-not $sshProcess.WaitForExit(500)) {
            $control = Enter-ControlLock
            try {
                $state = Read-State
                if ($state.instance -ne $Instance -or $state.worker.pid -ne $PID) { return }
                if ($state.stopRequested) { Stop-OwnedChild $state; return }
                if (-not $stableRecorded -and $connectionClock.Elapsed.TotalSeconds -ge $stableConnectionSeconds) {
                    $consecutiveShortFailures = 0
                    $stableRecorded = $true
                    $state.consecutiveShortFailures = 0
                    $state.connectionStable = $true
                    Write-State $state
                    Write-TunnelEvent -Event 'connection-stable' -Category 'none' `
                        -AliveSeconds $connectionClock.Elapsed.TotalSeconds -TotalAttempts $totalAttempts
                }
            } finally { $control.Dispose() }
        }
        $control = Enter-ControlLock
        try {
            $state = Read-State
            if ($state.instance -ne $Instance -or $state.worker.pid -ne $PID) { return }
            $connectionClock.Stop()
            $aliveSeconds = $connectionClock.Elapsed.TotalSeconds
            $exitCode = $sshProcess.ExitCode
            $outcome = Get-RetryOutcome $consecutiveShortFailures $aliveSeconds $exitCode $state.stopRequested
            $consecutiveShortFailures = $outcome.consecutiveShortFailures
            $state.child = $null
            $state.connectionStable = $false
            $state.consecutiveShortFailures = $consecutiveShortFailures
            $state.status = $(if ($state.stopRequested) { 'stopped' }
                elseif ($outcome.shouldRetry) { 'waiting-to-reconnect' } else { 'retry-budget-exhausted' })
            Write-State $state
            Write-TunnelEvent -Event 'attempt-exited' -Category $outcome.category -AliveSeconds $aliveSeconds `
                -ExitCode $exitCode -TotalAttempts $totalAttempts -ConsecutiveShortFailures $consecutiveShortFailures
            if (-not $outcome.shouldRetry -and -not $state.stopRequested) {
                Write-TunnelEvent -Event 'retry-budget-exhausted' -Category $outcome.category -AliveSeconds $aliveSeconds `
                    -ExitCode $exitCode -TotalAttempts $totalAttempts -ConsecutiveShortFailures $consecutiveShortFailures
            }
        } finally { $control.Dispose() }
        $sshProcess.Dispose()
        $sshProcess = $null
        if (-not $outcome.shouldRetry) { return }
    }
} finally {
    Complete-Worker $sshProcess
}
