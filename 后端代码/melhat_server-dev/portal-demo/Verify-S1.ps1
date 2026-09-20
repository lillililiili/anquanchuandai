$ErrorActionPreference = 'Stop'
$baseUrl = 'http://127.0.0.1:18085'
$accounts = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'runtime/accounts.local.json') | ConvertFrom-Json
function Login-Demo([string]$name) {
  $body = @{username=$name;password=$accounts.$name} | ConvertTo-Json
  $result = Invoke-RestMethod "$baseUrl/login" -Method Post -ContentType 'application/json' -Body $body
  if ($result.code -ne 200 -or !$result.token) { throw "Login failed for $name" }
  return @{Authorization='Bearer ' + $result.token}
}
function Assert-True($test,[string]$message) { if (!$test) { throw $message }; Write-Host "PASS $message" }
function Post-Demo($path,$body,$headers) { return Invoke-RestMethod ($baseUrl+$path) -Method Post -ContentType 'application/json' -Headers $headers -Body ($body|ConvertTo-Json) }
$owner = Login-Demo 'demo_owner'
$reader = Login-Demo 'demo_reader'
$ctx = Invoke-RestMethod "$baseUrl/api/portal/v1/context" -Headers $owner
Assert-True ($ctx.data.sites.Count -eq 3) 'Database-backed authorized stations'
$people = Invoke-RestMethod "$baseUrl/api/portal/v1/people?siteId=demo-site-1&pageSize=20" -Headers $owner
Assert-True ($people.data.total -eq 25 -and $people.data.items.Count -eq 20) 'Database paging'
$empty = Invoke-RestMethod "$baseUrl/api/portal/v1/people?siteId=demo-site-3" -Headers $owner
Assert-True ($empty.data.total -eq 0) 'Empty station'
try { Invoke-RestMethod "$baseUrl/api/portal/v1/people?siteId=demo-site-2" -Headers $reader | Out-Null; throw 'Cross-site access was allowed' } catch { if ([int]$_.Exception.Response.StatusCode -ne 403) { throw }; Write-Host 'PASS cross-site denied' }
$person = 'person-1-25'
$options = Invoke-RestMethod "$baseUrl/api/portal/v1/equipment-assignments/options?siteId=demo-site-1&personId=$person" -Headers $owner
if ($options.data.current.Count -ne 0) { throw 'Test person has assignments; choose/reset demo fixture before running mutation test.' }
$device = $options.data.available | Where-Object type -eq 'HELMET' | Select-Object -First 1
if (!$device) { throw 'No available helmet for integration test' }
$body = @{siteId='demo-site-1';personId=$person;deviceId=$device.id}
$key = [guid]::NewGuid().ToString()
$owner['Idempotency-Key'] = $key
$reader['Idempotency-Key'] = [guid]::NewGuid().ToString()
try { Post-Demo '/api/portal/v1/equipment-assignments' $body $reader | Out-Null; throw 'Readonly write was allowed' } catch { if ([int]$_.Exception.Response.StatusCode -ne 403) { throw }; Write-Host 'PASS readonly write denied' }
$issued = Post-Demo '/api/portal/v1/equipment-assignments' $body $owner
try {
  $repeat = Post-Demo '/api/portal/v1/equipment-assignments' $body $owner
  Assert-True ($repeat.data.id -eq $issued.data.id) 'Idempotent issue'
  $detail = Invoke-RestMethod "$baseUrl/api/portal/v1/people/${person}?siteId=demo-site-1" -Headers $owner
  Assert-True ($detail.data.equipment.data.helmet.assignmentState -eq 'ASSIGNED') 'Assignment persisted and read back'
  $owner['Idempotency-Key'] = [guid]::NewGuid().ToString()
  try { Post-Demo '/api/portal/v1/equipment-assignments' $body $owner | Out-Null; throw 'Duplicate assignment allowed' } catch { if ([int]$_.Exception.Response.StatusCode -ne 409) { throw }; Write-Host 'PASS duplicate assignment conflict' }
} finally {
  $owner['Idempotency-Key'] = [guid]::NewGuid().ToString()
  $returned = Post-Demo ('/api/portal/v1/equipment-assignments/'+$issued.data.id+'/return') @{siteId='demo-site-1';version=1} $owner
  Assert-True ($returned.data.version -eq 2) 'Return persisted'
}
$history = Invoke-RestMethod "$baseUrl/api/portal/v1/people/${person}/equipment-history?siteId=demo-site-1" -Headers $owner
Assert-True ($history.data.total -ge 2) 'Issue and return history persisted'
Write-Host 'Integration checks completed; audit and test history intentionally retained in demo database.'
