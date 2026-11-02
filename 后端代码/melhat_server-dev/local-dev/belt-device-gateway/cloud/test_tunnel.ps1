param([string]$TemporaryRoot = [System.IO.Path]::GetTempPath())

$ErrorActionPreference = 'Stop'

# Load only the named helper definitions; never run tunnel Start/Stop/Worker or SSH.
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot 'tunnel.ps1'), [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'tunnel.ps1 contains PowerShell syntax errors.' }
$helpers = @('Enter-ControlLock', 'Read-State', 'Write-State', 'Complete-Worker',
    'Get-RetryOutcome', 'Get-ExitCategory', 'Write-TunnelEvent', 'Assert-WorkerRecord', 'Test-RetryableStateReplaceError')
$definitions = $ast.FindAll({ param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in $helpers
}, $true)
if ($definitions.Count -ne $helpers.Count) { throw 'Expected tunnel helpers were not found.' }
. ([scriptblock]::Create(($definitions | ForEach-Object { $_.Extent.Text }) -join "`n"))

# Read the actual fixed budgets from the production script, rather than testing
# duplicate constants that could accidentally diverge from the worker.
$fixedNames = @('maximumConsecutiveShortFailures', 'retryDelaySeconds', 'stableConnectionSeconds',
    'maximumEventFileBytes', 'eventArchiveCount', 'stateReplaceAttempts', 'stateReplaceDelayMilliseconds')
$fixedAssignments = $ast.FindAll({ param($node)
    $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
    $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
    $node.Left.VariablePath.UserPath -in $fixedNames
}, $true)
if ($fixedAssignments.Count -ne $fixedNames.Count) { throw 'Expected fixed worker budgets were not found.' }
. ([scriptblock]::Create(($fixedAssignments | ForEach-Object { $_.Extent.Text }) -join "`n"))

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Start-TestSleeper {
    $process = Start-Process -FilePath (Get-Process -Id $PID).Path -WindowStyle Hidden -PassThru `
        -ArgumentList @('-NoLogo', '-NoProfile', '-NonInteractive', '-Command', '"Start-Sleep -Seconds 30"')
    $null = $process.Handle
    return $process
}

$localDirectory = Join-Path $TemporaryRoot ('belt-tunnel-test-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $localDirectory
$stateFile = Join-Path $localDirectory 'state.json'
$lockFile = Join-Path $localDirectory 'control.lock'
$eventFile = Join-Path $localDirectory 'events.jsonl'
$errorFile = Join-Path $localDirectory 'stderr.log'
Assert-True ($maximumEventFileBytes -eq 131072 -and $eventArchiveCount -eq 2) 'Production journal retention changed unexpectedly.'
$maximumEventFileBytes = 1024
$Instance = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
$scriptFile = Join-Path $PSScriptRoot 'tunnel.ps1'
$owned = $null
$observer = $null
$unrelated = $null
try {
    $legacyState = [pscustomobject]@{ version = 1; script = $scriptFile; instance = $Instance;
        worker = [pscustomobject]@{ pid = 123; commandLine = ($scriptFile + ' -Action Worker -Instance ' + $Instance) };
        child = $null; stopRequested = $false; status = 'ssh-running'; attempts = 8 }
    Write-State $legacyState
    Assert-WorkerRecord (Read-State)
    Assert-True ($null -eq (Read-State).totalAttempts -and (Read-State).attempts -eq 8) 'A legacy record was silently migrated or damaged.'
    $legacyState.worker.commandLine = $scriptFile + ' -Action Worker -Instance wrong-instance'
    $failed = $false
    try { Assert-WorkerRecord $legacyState }
    catch { $failed = $true }
    Assert-True $failed 'Legacy compatibility weakened the worker instance requirement.'
    Write-Output 'PASS: version 1 worker records remain accepted; a different launch instance is still refused.'

    # Repeated instant failures must leave five minutes of reconnect intervals,
    # and stop at a finite bound without sleeping or opening network connections.
    $failures = 0
    $retryIntervals = 0
    for ($attemptNumber = 1; $attemptNumber -le 31; $attemptNumber++) {
        $outcome = Get-RetryOutcome $failures 0 255
        $failures = $outcome.consecutiveShortFailures
        if ($outcome.shouldRetry) { $retryIntervals++ }
        Assert-True ($outcome.shouldRetry -eq ($attemptNumber -lt 31)) 'Consecutive failure budget terminated at the wrong attempt.'
    }
    Assert-True (($retryIntervals * $retryDelaySeconds) -eq 300) 'Rapid failures do not retain five minutes of retry intervals.'
    Assert-True ($failures -eq 31) 'Failure count was lost.'
    Write-Output 'PASS: 31 consecutive short failures provide 300 seconds of retry intervals, then stop.'

    $beforeBoundary = Get-RetryOutcome 30 119.999 255
    $atBoundary = Get-RetryOutcome 30 120 255
    Assert-True (-not $beforeBoundary.shouldRetry) 'A sub-120-second session incorrectly replenished the budget.'
    Assert-True ($atBoundary.shouldRetry -and $atBoundary.consecutiveShortFailures -eq 0) 'A stable session failed to replenish the budget.'
    $failures = 0
    for ($attemptNumber = 1; $attemptNumber -le 100; $attemptNumber++) {
        $duration = $(if ($attemptNumber % 10 -eq 0) { 120 } else { 1 })
        $outcome = Get-RetryOutcome $failures $duration 255
        $failures = $outcome.consecutiveShortFailures
        Assert-True $outcome.shouldRetry 'Lifetime connection count incorrectly exhausted the budget after stable sessions.'
    }
    Assert-True ((Get-RetryOutcome 0 200 255 $true).shouldRetry -eq $false) 'A requested stop attempted reconnect.'
    Assert-True ((Get-RetryOutcome 0 1 0).category -eq 'short-clean-exit') 'Clean short exits were misclassified.'
    Write-Output 'PASS: exact stability boundary resets consecutive failures; 100 lifetime sessions remain eligible; stop never reconnects.'

    foreach ($category in @('network-error', 'forward-rejected')) {
        $failures = 0
        for ($attemptNumber = 1; $attemptNumber -le 100; $attemptNumber++) {
            $outcome = Get-RetryOutcome $failures 1 255 $false $category
            $failures = $outcome.consecutiveShortFailures
            $expectedDelay = $(if ($attemptNumber -lt 31) { 10 } elseif ($attemptNumber -eq 31) { 60 }
                elseif ($attemptNumber -eq 32) { 120 } else { 300 })
            Assert-True ($outcome.shouldRetry -and $outcome.delaySeconds -eq $expectedDelay) 'Recoverable outage stopped or escaped its bounded cadence.'
            Assert-True ($outcome.status -eq $(if ($attemptNumber -lt 31) { 'waiting-to-reconnect' } else { 'cooldown-reconnect' })) 'Reconnect state is inaccurate.'
        }
        $recovered = Get-RetryOutcome 100 120 255 $false $category
        Assert-True ($recovered.shouldRetry -and $recovered.delaySeconds -eq 10 -and $recovered.consecutiveShortFailures -eq 0) 'A stable connection failed to reset cooldown.'
        Assert-True (-not (Get-RetryOutcome 100 1 255 $true $category).shouldRetry) 'Operator stop was bypassed by recovery.'
    }
    foreach ($category in @('host-key-failed','authentication-failed','exit-unknown')) {
        $outcome = Get-RetryOutcome 0 200 255 $false $category
        Assert-True (-not $outcome.shouldRetry -and $outcome.status -eq 'attention-required' -and $outcome.delaySeconds -eq 0) 'Permanent error entered automatic retry.'
    }
    Write-Output 'PASS: network/listener outages survive 100 failures with 60/120/300-second cooldown; identity/authentication failures still stop.'

    foreach ($case in @(
        @('Connection reset by peer','network-error'),
        @('Timeout, server is not responding.','network-error'),
        @('remote port forwarding failed for listen port','forward-rejected'),
        @('Host key verification failed.','host-key-failed'),
        @('Permission denied (publickey).','authentication-failed'),
        @('unrecognized test message','ssh-error'))) {
        [System.IO.File]::WriteAllText($errorFile, $case[0])
        Assert-True ((Get-ExitCategory 255 $false $errorFile) -eq $case[1]) 'SSH exit category was incorrect.'
    }
    Assert-True ((Get-ExitCategory $null $false $errorFile) -eq 'exit-unknown') 'An unavailable exit code was treated as success.'
    Assert-True ((Get-ExitCategory 0 $false $errorFile) -eq 'clean-exit') 'A clean exit was incorrectly parsed from stale stderr.'
    Assert-True ((Get-ExitCategory 255 $true $errorFile) -eq 'requested-stop') 'Requested stop was incorrectly parsed from stderr.'
    Write-Output 'PASS: local stderr is classified into fixed enums; no raw response is needed in diagnostics.'

    for ($eventNumber = 1; $eventNumber -le 40; $eventNumber++) {
        Write-TunnelEvent -Event 'attempt-exited' -Category 'short-ssh-failure' `
            -AliveSeconds 1.23456 -ExitCode 255 -TotalAttempts $eventNumber -ConsecutiveShortFailures 1
    }
    $eventPaths = @($eventFile, ($eventFile + '.1'), ($eventFile + '.2'))
    $eventCount = 0
    foreach ($path in $eventPaths) {
        Assert-True (Test-Path -LiteralPath $path) 'Event journal did not rotate through both bounded archives.'
        Assert-True ((Get-Item -LiteralPath $path).Length -le $maximumEventFileBytes) 'An event journal exceeded its byte bound.'
        foreach ($line in [System.IO.File]::ReadAllLines($path)) {
            $entry = $line | ConvertFrom-Json
            Assert-True ((@($entry.PSObject.Properties.Name) -join ',') -ceq
                'utc,event,aliveSeconds,exitCode,category,totalAttempts,consecutiveShortFailures,exitCategory,delaySeconds') 'Unexpected diagnostic fields could leak raw data.'
            # Newer PowerShell converts ISO strings to DateTime during parsing.
            Assert-True ($line -match '"utc"\s*:\s*"[^"]+Z"') 'Event timestamp was not explicit UTC.'
            Assert-True ($entry.aliveSeconds -eq 1.235 -and $entry.exitCode -eq 255) 'Event did not preserve duration and exit code.'
            $eventCount++
        }
    }
    Assert-True ($eventCount -lt 40 -and $eventCount -gt 0) 'Journal archives are not bounded.'
    Assert-True (-not (Test-Path -LiteralPath ($eventFile + '.3'))) 'An extra event archive escaped the retention limit.'
    $before = [System.IO.File]::ReadAllText($eventFile)
    $failed = $false
    try { Write-TunnelEvent -Event 'attempt-exited' -Category 'arbitrary-secret-response' }
    catch { $failed = $true }
    Assert-True $failed 'Arbitrary text was accepted as an event category.'
    Assert-True ([System.IO.File]::ReadAllText($eventFile) -ceq $before) 'Rejected event input was written to disk.'
    Write-Output 'PASS: event schema, UTC, values, strict category allowlist, rotation and total retention are bounded.'

    $blockedEventPath = $eventFile
    $eventFile = Join-Path $localDirectory 'missing-parent/events.jsonl'
    Write-TunnelEvent -Event 'attempt-exited' -Category 'short-ssh-failure' -ExitCategory 'network-error' -DelaySeconds 300
    Write-State ([pscustomobject]@{ status = 'cooldown-reconnect' })
    Assert-True ((Read-State).eventLogError -eq $true) 'A failed diagnostic write was not recorded in state.'
    $eventFile = $blockedEventPath
    Write-TunnelEvent -Event 'attempt-exited' -Category 'short-ssh-failure' -ExitCategory 'network-error' -DelaySeconds 300
    Write-State ([pscustomobject]@{ status = 'cooldown-reconnect' })
    Assert-True ((Read-State).eventLogError -eq $false) 'Recovered diagnostics did not clear their error flag.'
    $lastEvent = ([System.IO.File]::ReadAllLines($eventFile) | Select-Object -Last 1) | ConvertFrom-Json
    Assert-True ($lastEvent.exitCategory -eq 'network-error' -and $lastEvent.delaySeconds -eq 300) 'Exit cause/cooldown were not retained.'
    Write-Output 'PASS: diagnostic filesystem failures do not throw or stop reconnection, and status exposes recovery.'

    Write-State ([pscustomobject]@{ status = 'first' })
    Write-State ([pscustomobject]@{ status = 'second' })
    Assert-True ((Read-State).status -eq 'second') 'Atomic state creation/update failed.'

    Assert-True ($stateReplaceAttempts -eq 20 -and $stateReplaceDelayMilliseconds -eq 100) 'State replacement retry budget changed unexpectedly.'
    Assert-True ((($stateReplaceAttempts - 1) * $stateReplaceDelayMilliseconds) -lt 5000) 'State retry delay exceeds the control-lock wait budget.'
    foreach ($code in @(32, 33, 1175)) {
        $failure = [System.IO.IOException]::new('fixed test failure', (-2147024896 + $code))
        $wrapped = [System.Exception]::new('fixed wrapper', $failure)
        Assert-True (Test-RetryableStateReplaceError $wrapped) 'A retryable native file error was not recognized through its wrapper.'
    }
    foreach ($code in @(2, 5, 17, 87, 1176, 1177)) {
        $failure = [System.IO.IOException]::new('fixed test failure', (-2147024896 + $code))
        Assert-True (-not (Test-RetryableStateReplaceError $failure)) 'A permanent or partial-rename failure was incorrectly retried.'
    }
    Assert-True (-not (Test-RetryableStateReplaceError ([UnauthorizedAccessException]::new('fixed test failure')))) 'Permission failures were incorrectly retried.'
    Write-Output 'PASS: bounded state retries recognize only Windows 32/33/1175; permission and partial-rename errors remain fatal.'

    # Release a real Windows file handle from an isolated in-process runspace.
    # It denies deletion while held, just like an external reader that did not
    # opt into FileShare.Delete; no SSH or real tunnel state is touched.
    $ready = [System.Threading.ManualResetEventSlim]::new($false)
    $reader = [PowerShell]::Create()
    $pendingRead = $null
    try {
        $null = $reader.AddScript({ param($path, $readySignal)
            $held = [System.IO.File]::Open($path, [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
            try {
                $beforeRead = [System.IO.File]::ReadAllText($path)
                $readySignal.Set()
                Start-Sleep -Milliseconds 350
                [System.IO.File]::ReadAllText($path) -ceq $beforeRead
            } finally { $held.Dispose() }
        }).AddArgument($stateFile).AddArgument($ready)
        $pendingRead = $reader.BeginInvoke()
        Assert-True ($ready.Wait(5000)) 'The isolated state-file reader did not acquire its handle.'
        Write-State ([pscustomobject]@{ status = 'after-transient-reader' })
        $readerResult = $reader.EndInvoke($pendingRead)
        Assert-True ($reader.Streams.Error.Count -eq 0 -and $readerResult.Count -eq 1 -and $readerResult[0] -eq $true) 'State changed or disappeared while the reader denied replacement.'
        Assert-True ((Read-State).status -eq 'after-transient-reader') 'State replacement did not recover after the reader released its handle.'
        Assert-True (@(Get-ChildItem -LiteralPath $localDirectory -Filter '*.tmp' -Force).Count -eq 0) 'Successful replacement left a temporary state file.'
    } finally {
        if ($null -ne $pendingRead -and -not $pendingRead.IsCompleted) { $reader.Stop() }
        $reader.Dispose()
        $ready.Dispose()
    }
    Write-Output 'PASS: transient Windows reader contention preserves old JSON then completes atomic replacement after release.'

    # A real Windows sharing violation must leave the existing JSON untouched.
    $before = [System.IO.File]::ReadAllText($stateFile)
    $locked = [System.IO.File]::Open($stateFile, [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    $failed = $false
    try {
        try { Write-State ([pscustomobject]@{ status = 'must-not-replace' }) }
        catch { $failed = $true }
    } finally { $locked.Dispose() }
    Assert-True $failed 'The locked state file unexpectedly allowed replacement.'
    Assert-True ([System.IO.File]::ReadAllText($stateFile) -ceq $before) 'Failed replacement damaged the prior state.'
    Assert-True (@(Get-ChildItem -LiteralPath $localDirectory -Filter '*.tmp' -Force).Count -eq 0) 'Temporary state files were not cleaned up.'
    Write-Output 'PASS: atomic state write preserves the prior JSON after replacement failure.'

    $unrelated = Start-TestSleeper
    $owned = Start-TestSleeper
    $observer = Get-Process -Id $owned.Id
    $null = $observer.Handle
    [System.IO.File]::WriteAllText($stateFile, '{broken-json')
    $failed = $false
    try { Complete-Worker $owned }
    catch { $failed = $true }
    $owned = $null
    Assert-True $failed 'Unreadable state should be reported.'
    Assert-True ($observer.WaitForExit(2000)) 'Owned process survived an unreadable journal.'
    Assert-True (-not $unrelated.HasExited) 'Cleanup stopped an unrelated process.'
    $observer.Dispose()
    $observer = $null
    Write-Output 'PASS: corrupt state still closes the worker-owned process and preserves unrelated processes.'

    $newState = [pscustomobject]@{ instance = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
        worker = [pscustomobject]@{ pid = $PID }; child = 'new-run-child'; status = 'new-run' }
    Write-State $newState
    $before = [System.IO.File]::ReadAllText($stateFile)
    $owned = Start-TestSleeper
    $observer = Get-Process -Id $owned.Id
    $null = $observer.Handle
    Complete-Worker $owned
    $owned = $null
    Assert-True ($observer.WaitForExit(2000)) 'Prior worker left its child alive after the state instance changed.'
    Assert-True ([System.IO.File]::ReadAllText($stateFile) -ceq $before) 'Prior worker overwrote a newer run state.'
    Assert-True (-not $unrelated.HasExited) 'Cleanup stopped an unrelated process.'
    Write-Output 'PASS: changed instance preserves the newer state while stopping only the prior worker child.'

    Write-State ([pscustomobject]@{ instance = $Instance; worker = [pscustomobject]@{ pid = $PID };
        child = $null; stopRequested = $false; status = 'retry-budget-exhausted';
        totalAttempts = 52; consecutiveShortFailures = 31; connectionStable = $true })
    Complete-Worker $null
    Assert-True ((Read-State).status -eq 'retry-budget-exhausted') 'Cleanup hid the reason retries stopped.'
    Assert-True ((Read-State).connectionStable -eq $false) 'Cleanup left a stopped connection marked stable.'
    $lastEvent = ([System.IO.File]::ReadAllLines($eventFile) | Select-Object -Last 1) | ConvertFrom-Json
    Assert-True ($lastEvent.totalAttempts -eq 52 -and $lastEvent.consecutiveShortFailures -eq 31) 'Lifetime and consecutive counters were confused.'
    Write-Output 'PASS: final cleanup retains retry exhaustion and distinct lifetime/consecutive counters.'
    Write-State ([pscustomobject]@{ instance = $Instance; worker = [pscustomobject]@{ pid = $PID };
        child = $null; stopRequested = $false; status = 'attention-required';
        totalAttempts = 1; consecutiveShortFailures = 1; connectionStable = $false })
    Complete-Worker $null
    Assert-True ((Read-State).status -eq 'attention-required') 'Cleanup hid an authentication/identity failure.'
    Write-Output 'PASS: final cleanup retains attention-required for operator intervention.'
    Write-Output 'All 14 tunnel test groups passed; no SSH process or network connection was started.'
} finally {
    foreach ($process in @($owned, $observer, $unrelated)) {
        if ($null -ne $process) {
            try { if (-not $process.HasExited) { $process.Kill(); $null = $process.WaitForExit(2000) } }
            finally { $process.Dispose() }
        }
    }
    # This directory is newly created by the test; remove only its known files.
    foreach ($path in @($stateFile, $lockFile, $eventFile, ($eventFile + '.1'), ($eventFile + '.2'), $errorFile)) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
    }
    if (Test-Path -LiteralPath $localDirectory) { Remove-Item -LiteralPath $localDirectory }
}
