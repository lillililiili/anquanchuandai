# Offline safety checks. Load only pure function declarations, never run startup.
$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot 'start-wearable.ps1'
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Startup script has PowerShell syntax errors.' }
foreach ($name in @('Same-Path', 'Quote-Argument', 'Test-NodeCommand', 'Test-ViteSource')) {
    $function = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }.GetNewClosure(), $true)
    if (-not $function) { throw ('Missing test function: ' + $name) }
    . ([scriptblock]::Create($function.Extent.Text))
}
$passed = 0
function Assert([bool]$Condition, [string]$Label) {
    if (-not $Condition) { throw ('FAIL: ' + $Label) }
    $script:passed++
}
$nodePath = 'C:\node\node.exe'
$gateway = @{ kind='gateway'; script='D:\wearable\device-gateway\cli.mjs' }
$process = [pscustomobject]@{ExecutablePath=$nodePath;CommandLine='"C:\node\node.exe" "D:\wearable\device-gateway\cli.mjs"'}
Assert (Test-NodeCommand $process $gateway $nodePath) 'Exact gateway executable and entry point are accepted'
$process.CommandLine = '"C:\node\node.exe" "D:\other\device-gateway\cli.mjs"'
Assert (-not (Test-NodeCommand $process $gateway $nodePath)) 'Other checkout is rejected'
$process.CommandLine = '"C:\node\node.exe" "D:\wearable\device-gateway\cli.mjs" --check'
Assert (-not (Test-NodeCommand $process $gateway $nodePath)) 'Configuration checker is not a running gateway'
$process.CommandLine = '"C:\node\node.exe" "D:\wearable\device-gateway\cli.mjs.old"'
Assert (-not (Test-NodeCommand $process $gateway $nodePath)) 'Substring path match is rejected'
$process.CommandLine = '"C:\node\node.exe" "D:\wearable\device-gateway\cli.mjs"'
$process.ExecutablePath = 'C:\other\node.exe'
Assert (-not (Test-NodeCommand $process $gateway $nodePath)) 'Unexpected executable is rejected'
$process.ExecutablePath = $nodePath
$vite = @{kind='vite';port=5191;root='D:\wearable\portal';script='D:\wearable\portal\node_modules\vite\bin\vite.js'}
$process.CommandLine = '"C:\node\node.exe" "D:\wearable\portal\node_modules\vite\bin\vite.js" "D:\wearable\portal" --host 127.0.0.1 --port 5191 --strictPort'
Assert (Test-NodeCommand $process $vite $nodePath) 'New absolute Vite launch is accepted'
$process.CommandLine = '"C:\node\node.exe" node_modules/vite/bin/vite.js --host 127.0.0.1 --port 5191 --strictPort'
Assert (Test-NodeCommand $process $vite $nodePath) 'Legacy relative Vite passes command check before SFC identity check'
$process.CommandLine = '"C:\node\node.exe" node_modules/vite/bin/vite.js --host 0.0.0.0 --port 5191 --strictPort'
Assert (-not (Test-NodeCommand $process $vite $nodePath)) 'Non-loopback Vite arguments are rejected'
$process.CommandLine = '"C:\node\node.exe" node_modules/vite/bin/vite.js --host 127.0.0.1 --port 5181 --strictPort'
Assert (-not (Test-NodeCommand $process $vite $nodePath)) 'Another port is rejected'
$process.CommandLine = '"C:\node\node.exe" node_modules/vite/bin/vite.js --host 127.0.0.1 --port 5191 --config other.js'
Assert (-not (Test-NodeCommand $process $vite $nodePath)) 'Unexpected Vite configuration is rejected'
Assert (Test-ViteSource "export default fn(c, [['__file',`"D:/wearable/portal/src/App.vue`"]])" 'D:\wearable\portal\src\App.vue') 'Exact served SFC identity is accepted'
Assert (-not (Test-ViteSource "export default fn(c, [['__file',`"D:/other/portal/src/App.vue`"]])" 'D:\wearable\portal\src\App.vue')) 'Other root served by relative Vite is rejected'
Assert (-not (Test-ViteSource 'D:/wearable/portal/src/App.vue' 'D:\wearable\portal\src\App.vue')) 'A loose path occurrence is not enough'
$threw = $false
try { $null = Quote-Argument 'bad"argument' } catch { $threw = $true }
Assert $threw 'Quoted process argument injection is rejected'
$commands = @($ast.FindAll({param($node) $node -is [System.Management.Automation.Language.CommandAst]}, $true))
Assert (-not ($commands | Where-Object { $_.GetCommandName() -in @('Stop-Process','Remove-Item','Unregister-ScheduledTask','Register-ScheduledTask') })) 'Startup never kills processes, deletes files, or creates startup tasks'
$starts = @($commands | Where-Object { $_.GetCommandName() -eq 'Start-Process' })
Assert ($starts.Count -eq 1 -and $starts[0].Extent.Text -match '-WindowStyle\s+Hidden') 'New node service processes are hidden'
$text = [IO.File]::ReadAllText($scriptPath)
Assert ($text -notmatch 'docker\s+compose|\bpm\s+clear\b|\badb\s+install\b') 'No container rebuild or application data reset is present'
Write-Output ("PASS: $passed offline checks; startup was not executed.")
