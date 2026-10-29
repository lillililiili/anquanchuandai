param([string]$TemporaryRoot = [System.IO.Path]::GetTempPath())

$ErrorActionPreference = 'Stop'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot 'tunnel.ps1'), [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'tunnel.ps1 contains PowerShell syntax errors.' }
# Load isolated helpers only. Never execute Start/Stop/Status/Worker, SSH, or any process command.
$helpers = @('Get-RetryDecision', 'Get-ExitCategory', 'Wait-RetryDelay', 'Write-ConnectionEvent')
$definitions = $ast.FindAll({ param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in $helpers
}, $true)
if ($definitions.Count -ne $helpers.Count) { throw 'Expected retry helpers were not found.' }
. ([scriptblock]::Create(($definitions | ForEach-Object { $_.Extent.Text }) -join "`n"))

function Assert-Equal($Actual, $Expected, [string]$Message) {
    if ($Actual -cne $Expected) { throw $Message }
}
$caseCount = 0
function Test-Case([string]$Name, [scriptblock]$Body) {
    & $Body
    $script:caseCount++
    Write-Output ('PASS: ' + $Name)
}

$folder = Join-Path $TemporaryRoot ('helmet-tunnel-retry-test-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $folder
$logFile = Join-Path $folder 'fake-ssh-error.log'
$eventsFile = Join-Path $folder 'fake-connection-events.jsonl'
try {
    Test-Case 'unknown SSH errors retain the bounded 12-short-failure budget' {
        $failures = 0
        for ($launch = 1; $launch -le 12; $launch++) {
            $decision = Get-RetryDecision $failures 5 $false
            $failures = $decision.consecutiveFailures
            Assert-Equal $failures $launch 'The short-failure counter is not consecutive.'
            Assert-Equal $decision.retry ($launch -lt 12) 'Retry limit has an off-by-one error.'
        }
        Assert-Equal $decision.status 'retry-limit-reached' 'Exhaustion must have an explicit status.'
    }
    Test-Case 'transient failures retain quick retries then cool down at 60, 120 and capped 300 seconds' {
        foreach ($category in @('network-error', 'forward-rejected')) {
            $failures = 0
            for ($launch = 1; $launch -le 16; $launch++) {
                $decision = Get-RetryDecision $failures 1 $false 12 60 $category
                $failures = $decision.consecutiveFailures
                Assert-Equal $failures $launch 'Cooldown lost the consecutive failure count.'
                Assert-Equal $decision.retry $true 'A recoverable failure permanently stopped the worker.'
                $expectedDelay = $(if ($launch -lt 12) { 10 } elseif ($launch -eq 12) { 60 } elseif ($launch -eq 13) { 120 } else { 300 })
                Assert-Equal $decision.delaySeconds $expectedDelay 'Cooldown delay is incorrect.'
                Assert-Equal $decision.status $(if ($launch -lt 12) { 'waiting-to-reconnect' } else { 'cooldown-reconnect' }) 'Cooldown status is ambiguous.'
            }
            Assert-Equal (Get-RetryDecision 1000 0 $false 12 60 $category).delaySeconds 300 'Long outages exceeded the bounded delay.'
        }
    }
    Test-Case 'permanent identity, authentication and worker failures stop without consuming cooldowns' {
        foreach ($category in @('host-key-failed', 'authentication-failed', 'launch-failed', 'worker-error', 'exit-unknown')) {
            foreach ($runSeconds in @(0, 60, 600)) {
                $decision = Get-RetryDecision 14 $runSeconds $false 12 60 $category
                Assert-Equal $decision.retry $false 'An unsafe permanent failure retried.'
                Assert-Equal $decision.status 'attention-required' 'A permanent failure lost its explicit status.'
                Assert-Equal $decision.delaySeconds 0 'A permanent failure scheduled a reconnect.'
            }
        }
    }
    Test-Case 'stable process survival resets cooldown while categories share the short-failure counter' {
        $first = Get-RetryDecision 11 1 $false 12 60 'network-error'
        $second = Get-RetryDecision $first.consecutiveFailures 1 $false 12 60 'forward-rejected'
        Assert-Equal $second.delaySeconds 120 'Changing transient category restarted the fast budget.'
        $stable = Get-RetryDecision $second.consecutiveFailures 60 $false 12 60 'network-error'
        Assert-Equal $stable.consecutiveFailures 0 'Stable survival did not restore the fast budget.'
        Assert-Equal $stable.delaySeconds 10 'Stable survival retained the old cooldown.'
        Assert-Equal (Get-RetryDecision 13 59.999 $false 12 60 'network-error').delaySeconds 300 'A run below 60 seconds reset cooldown.'
    }
    Test-Case 'Stop interrupts a 300-second cooldown on the next 500ms check without sleeping in tests' {
        $script:delayTicks = 0
        $script:pauseValues = [System.Collections.Generic.List[int]]::new()
        $continue = Wait-RetryDelay 300 { $script:delayTicks -ge 3 } {
            param($Milliseconds)
            $script:pauseValues.Add($Milliseconds)
            $script:delayTicks++
        }
        Assert-Equal $continue $false 'Stop failed to cancel the cooldown.'
        Assert-Equal $script:delayTicks 3 'The cooldown continued after cancellation.'
        Assert-Equal (@($script:pauseValues | Where-Object { $_ -ne 500 }).Count) 0 'A wait slice can block Stop longer than 500ms.'
        $continue = Wait-RetryDelay 300 { $true } { throw 'An already stopped worker must not sleep.' }
        Assert-Equal $continue $false 'An already requested Stop was ignored.'
        $decision = Get-RetryDecision 1000 0 $true 12 60 'network-error'
        Assert-Equal $decision.retry $false 'Stop was overridden by transient retry.'
        Assert-Equal $decision.delaySeconds 0 'Stop left a retry delay.'
    }
    Test-Case 'a completed short delay permits exactly one next attempt' {
        $script:delayTicks = 0
        $continue = Wait-RetryDelay 10 { $false } { param($Milliseconds) $script:delayTicks++ }
        Assert-Equal $continue $true 'A normal retry delay was cancelled.'
        Assert-Equal $script:delayTicks 20 'A 10-second delay did not use twenty 500ms slices.'
    }
    Test-Case '60 seconds is the exact stable threshold and restores a full new budget' {
        Assert-Equal (Get-RetryDecision 11 59.999 $false).retry $false 'A short run reset the budget.'
        $stable = Get-RetryDecision 11 60 $false
        Assert-Equal $stable.consecutiveFailures 0 'A stable run did not reset the budget.'
        Assert-Equal $stable.retry $true 'A stable disconnection cannot reconnect.'
        $failures = $stable.consecutiveFailures
        for ($launch = 1; $launch -le 12; $launch++) {
            $decision = Get-RetryDecision $failures 1 $false
            $failures = $decision.consecutiveFailures
            Assert-Equal $decision.retry ($launch -lt 12) 'The restored budget is not exactly 12 failures.'
        }
    }
    Test-Case 'stable runs may recur without turning short failures into unlimited retries' {
        foreach ($runSeconds in @(600, 60, 86400)) {
            $stable = Get-RetryDecision 10 $runSeconds $false
            Assert-Equal $stable.consecutiveFailures 0 'Stable survival must reset prior failures.'
            $short = Get-RetryDecision $stable.consecutiveFailures 0 $false
            Assert-Equal $short.consecutiveFailures 1 'The next short failure must consume a fresh slot.'
        }
    }
    Test-Case 'requested Stop neither increases the failure count nor retries' {
        foreach ($runSeconds in @(0, 59, 60, 600)) {
            $decision = Get-RetryDecision 11 $runSeconds $true
            Assert-Equal $decision.consecutiveFailures 11 'Stop changed failure accounting.'
            Assert-Equal $decision.retry $false 'Stop attempted a reconnect.'
            Assert-Equal $decision.status 'stopped' 'Stop status was not preserved.'
        }
    }
    Test-Case 'exit classification emits only small enums, never the synthetic secret tail' {
        $examples = @{
            'remote port forwarding failed for listen port 28086' = 'forward-rejected'
            'Permission denied (publickey).' = 'authentication-failed'
            'Host key verification failed.' = 'host-key-failed'
            'Connection timed out' = 'network-error'
            'Connection reset by peer' = 'network-error'
            'unrecognized failure' = 'ssh-error'
        }
        foreach ($entry in $examples.GetEnumerator()) {
            [System.IO.File]::WriteAllText($logFile, ('synthetic-private-marker /private/path' + "`n" + $entry.Key))
            $category = Get-ExitCategory 255 $false $logFile
            Assert-Equal $category $entry.Value 'Error classification did not return the expected enum.'
            Assert-Equal ($category -match 'synthetic-private-marker|/private/path') $false 'Diagnostic contents escaped into metadata.'
        }
    }
    Test-Case 'missing exit code stays unknown and Stop takes precedence' {
        Assert-Equal (Get-ExitCategory $null $false $logFile) 'exit-unknown' 'Unknown exit code became success.'
        Assert-Equal (Get-ExitCategory 0 $false $logFile) 'clean-exit' 'Zero exit code was not classified.'
        Assert-Equal (Get-ExitCategory 255 $true $logFile) 'requested-stop' 'Requested Stop used the old SSH error.'
        Assert-Equal (Get-ExitCategory $null $true $logFile) 'requested-stop' 'Requested Stop requires an exit code.'
    }
    Test-Case 'classification uses only the existing 12-line tail and tolerates missing logs' {
        $lines = @('Host key verification failed.') + @(1..12 | ForEach-Object { 'unclassified tail' })
        [System.IO.File]::WriteAllLines($logFile, [string[]]$lines)
        Assert-Equal (Get-ExitCategory 255 $false $logFile) 'ssh-error' 'An old error outside the tail was reused.'
        Assert-Equal (Get-ExitCategory 255 $false (Join-Path $folder 'absent.log')) 'ssh-error' 'A missing log broke classification.'
    }
    Test-Case 'connection history whitelists state and never records credentials or raw errors' {
        $state = [pscustomobject]@{ worker = @{pid=123; commandLine='synthetic-private-marker'};
            child = @{pid=124; executable='/private/path'}; totalAttempts=46; consecutiveFailures=12;
            status='cooldown-reconnect'; lastExitCategory='forward-rejected'; lastExitCode=255;
            lastRunSeconds=1; retryDelaySeconds=60; extraSecret='synthetic-private-marker' }
        Write-ConnectionEvent $state 'ssh-exit'
        Assert-Equal $state.eventLogError $false 'A valid event could not be written.'
        $text = [System.IO.File]::ReadAllText($eventsFile)
        Assert-Equal ($text -match 'synthetic-private-marker|/private/path|commandLine|extraSecret') $false 'Sensitive fields escaped into connection history.'
        $event = $text | ConvertFrom-Json
        Assert-Equal $event.totalAttempts 46 'Attempt number was lost.'
        Assert-Equal $event.sshPid 124 'Exit event lost its child identity.'
        Assert-Equal $event.delaySeconds 60 'Exit event lost the planned cooldown.'
        $state.status = 'synthetic-private-marker'
        $state.lastExitCategory = 'synthetic-private-marker'
        Write-ConnectionEvent $state 'ssh-start'
        Assert-Equal $state.eventLogError $false 'Second event could not replace the bounded log atomically.'
        $last = [System.IO.File]::ReadAllLines($eventsFile)[-1] | ConvertFrom-Json
        Assert-Equal $last.status 'unknown' 'An arbitrary status string escaped.'
        Assert-Equal $last.exitCategory $null 'An arbitrary exit category escaped.'
    }
    Test-Case 'connection history retains the latest 512 events within its byte limit across writes' {
        $prototype = [System.IO.File]::ReadAllLines($eventsFile)[0] | ConvertFrom-Json
        $seed = foreach ($number in 1..512) { $prototype.totalAttempts = $number; $prototype | ConvertTo-Json -Compress }
        [System.IO.File]::WriteAllLines($eventsFile, [string[]]$seed)
        $state = [pscustomobject]@{worker=@{pid=123};child=$null;totalAttempts=513;consecutiveFailures=13;
            status='cooldown-reconnect';lastExitCategory='network-error';lastExitCode=255;lastRunSeconds=1;retryDelaySeconds=120}
        Write-ConnectionEvent $state 'ssh-exit'
        Assert-Equal $state.eventLogError $false 'Bounded history rotation failed.'
        $lines = [System.IO.File]::ReadAllLines($eventsFile)
        Assert-Equal $lines.Length 512 'History has an unbounded number of events.'
        Assert-Equal (($lines[0] | ConvertFrom-Json).totalAttempts) 2 'Oldest event was not discarded.'
        Assert-Equal (($lines[-1] | ConvertFrom-Json).totalAttempts) 513 'Newest event was lost.'
        Assert-Equal ((Get-Item -LiteralPath $eventsFile).Length -le 262144) $true 'History exceeded its byte limit.'
    }
    Test-Case 'unknown history is preserved and cannot stop a reconnect decision' {
        [System.IO.File]::WriteAllText($eventsFile, 'unknown existing fixture')
        $state = [pscustomobject]@{worker=@{pid=123};child=$null;totalAttempts=1;consecutiveFailures=1;
            status='waiting-to-reconnect';lastExitCategory='network-error';lastExitCode=255;lastRunSeconds=1;retryDelaySeconds=10}
        Write-ConnectionEvent $state 'ssh-exit'
        Assert-Equal $state.eventLogError $true 'A rejected log was not reported.'
        Assert-Equal ([System.IO.File]::ReadAllText($eventsFile)) 'unknown existing fixture' 'An unknown existing log was overwritten.'
        Assert-Equal (Get-RetryDecision 12 1 $false 12 60 'network-error').retry $true 'Logging failure affected retry.'
        Assert-Equal (@(Get-ChildItem -LiteralPath $folder -Filter '*.tmp').Count) 0 'Failed logging left temporary files.'
    }
    Test-Case 'a locked event log reports failure without changing history or throwing' {
        $before = [System.IO.File]::ReadAllText($eventsFile)
        $state = [pscustomobject]@{worker=@{pid=123};child=$null;totalAttempts=1;consecutiveFailures=1;
            status='waiting-to-reconnect';lastExitCategory='network-error';lastExitCode=255;lastRunSeconds=1;retryDelaySeconds=10}
        $held = [System.IO.File]::Open($eventsFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        try { Write-ConnectionEvent $state 'ssh-exit' } finally { $held.Dispose() }
        Assert-Equal $state.eventLogError $true 'A locked event log was not reported.'
        Assert-Equal ([System.IO.File]::ReadAllText($eventsFile)) $before 'A locked history was changed.'
    }
    Write-Output ('All ' + $caseCount + ' isolated retry tests passed; no process or network connection was started.')
} finally {
    # Only this newly created directory and its two known fixture files are removed.
    if (Test-Path -LiteralPath $logFile) { Remove-Item -LiteralPath $logFile }
    if (Test-Path -LiteralPath $eventsFile) { Remove-Item -LiteralPath $eventsFile }
    if (Test-Path -LiteralPath $folder) { Remove-Item -LiteralPath $folder }
}
