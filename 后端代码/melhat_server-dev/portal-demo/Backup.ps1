$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$demoContainer = 'wearable-portal-demo-mysql-1'
$project = & docker inspect $demoContainer --format '{{index .Config.Labels "com.docker.compose.project"}}'
if ($LASTEXITCODE -ne 0 -or $project.Trim() -ne 'wearable-portal-demo') { throw 'Refusing non-demo container' }
$marker = & docker exec $demoContainer sh -c 'MYSQL_PWD="$MYSQL_PASSWORD" mysql -uportal_demo -N wearable_portal_demo -e "SELECT environment FROM portal_demo_schema WHERE version=1"'
if ($LASTEXITCODE -ne 0 -or $marker.Trim() -ne 'wearable-portal-demo') { throw 'Refusing unmarked database' }
New-Item -ItemType Directory -Force -Path backups | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
& docker exec $demoContainer sh -c 'MYSQL_PWD="$MYSQL_PASSWORD" mysqldump -uportal_demo --single-transaction --no-tablespaces --set-gtid-purged=OFF wearable_portal_demo > /tmp/portal-demo-backup.sql'
if ($LASTEXITCODE -ne 0) { throw 'Database backup failed' }
$target = Join-Path $PSScriptRoot "backups/demo-$stamp.sql"
& docker cp "${demoContainer}:/tmp/portal-demo-backup.sql" $target
if ($LASTEXITCODE -ne 0) { throw 'Backup copy failed' }
Write-Host "Database backup: $target (does not include uploaded media)."
