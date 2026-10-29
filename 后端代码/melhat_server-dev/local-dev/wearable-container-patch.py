"""Compatible container rollout using deployment authority, without application login.

Only SELECT statements and mysqldump use the database container's existing backup
environment. No account document/session file, authenticated API, maintenance write,
data cleanup, SQL import, or credential-bearing public request is used.
"""
import argparse
import datetime as dt
import hashlib
import json
import pathlib
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
LIVE, MYSQL, DATABASE = 'melhat-backend', 'melhat-mysql', 'new-helmet'
STABLE_TABLES = ('wearable_device', 'wearable_person', 'wearable_account', 'wearable_role', 'wearable_assignment')
HISTORY_TABLES = ('wearable_event', 'wearable_location', 'helmet_location_fix',
                  'wearable_device_report', 'external_integration', 'external_data_record', 'wearable_assignment_history')


def now():
    return dt.datetime.now(dt.timezone.utc).isoformat()


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def docker(*args, data=None, output=None, timeout=120):
    try:
        result = subprocess.run(['docker', *args], input=data, stdout=output or subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=timeout)
    except subprocess.TimeoutExpired:
        # TimeoutExpired includes argv; deployment arguments can contain opaque secrets.
        raise RuntimeError('Docker operation timed out: ' + args[0]) from None
    if result.returncode:
        raise RuntimeError('Docker operation failed: ' + args[0])
    return result.stdout


def inspect(name):
    return json.loads(docker('inspect', name))[0]


def read_sql(statement):
    if not statement.lstrip().upper().startswith('SELECT ') or ';' in statement.rstrip().rstrip(';'):
        raise RuntimeError('Only one read-only SELECT statement is allowed')
    return docker('exec', '-i', MYSQL, 'sh', '-c',
                  'exec mysql --default-character-set=utf8mb4 -uroot -p"$MYSQL_ROOT_PASSWORD" -N -B "$1"',
                  'wearable-container-patch', DATABASE, data=statement.encode('utf-8'), timeout=600).decode().strip()


def snapshot():
    counts = ','.join("'" + name + "',(SELECT COUNT(*) FROM `" + name + "`)" for name in STABLE_TABLES + HISTORY_TABLES)
    return json.loads(read_sql("SELECT JSON_OBJECT('mode',(SELECT mode FROM wearable_runtime_control WHERE control_key='global'),"
        "'reportWatermark',(SELECT COALESCE(MAX(sequence),0) FROM wearable_device_report),"
        "'pendingReports',(SELECT COUNT(*) FROM wearable_device_report WHERE processed_at IS NULL),"
        "'watchVisible',(SELECT JSON_EXTRACT(body,'$.simulatedWatchVisible') FROM wearable_business_config WHERE id=1),"
        "'dataVersion',(SELECT JSON_UNQUOTE(JSON_EXTRACT(body,'$.dataVersion')) FROM wearable_business_config WHERE id=1),"
        "'inventory',(SELECT GROUP_CONCAT(id ORDER BY id SEPARATOR ',') FROM wearable_device),"
        "'activeAssignments',(SELECT GROUP_CONCAT(CONCAT_WS('|',id,JSON_UNQUOTE(JSON_EXTRACT(body,'$.deviceId')),"
        "JSON_UNQUOTE(JSON_EXTRACT(body,'$.personId')),JSON_UNQUOTE(JSON_EXTRACT(body,'$.version'))) ORDER BY id SEPARATOR ',') "
        "FROM wearable_assignment WHERE JSON_EXTRACT(body,'$.active')=true),"
        "'namespaces',(SELECT GROUP_CONCAT(namespace ORDER BY namespace SEPARATOR ',') FROM wearable_business_meta),"
        "'counts',JSON_OBJECT(" + counts + "))"))


def verify_preservation(before, after):
    if after['mode'] != 'ACTIVE' or after['namespaces'] != before['namespaces']:
        raise RuntimeError('Current maintenance state or initialized storage changed')
    for key in ('watchVisible', 'dataVersion', 'inventory', 'activeAssignments'):
        if before[key] != after[key]:
            raise RuntimeError('Preserved business configuration changed: ' + key)
    for table in STABLE_TABLES:
        if before['counts'][table] != after['counts'][table]:
            raise RuntimeError('Protected business row count changed: ' + table)
    for table in HISTORY_TABLES:
        if after['counts'][table] < before['counts'][table]:
            raise RuntimeError('Persisted history count decreased: ' + table)
    if int(after['reportWatermark']) < int(before['reportWatermark']):
        raise RuntimeError('Raw report watermark regressed')


def recreate_args(previous, image):
    networks = list(previous['NetworkSettings']['Networks'])
    if len(networks) != 1:
        raise RuntimeError('Expected one existing deployment network')
    args = ['run', '-d', '--name', LIVE, '--network', networks[0]]
    for alias in previous['NetworkSettings']['Networks'][networks[0]].get('Aliases') or []:
        if alias not in (LIVE, previous.get('Id'), str(previous.get('Id', ''))[:12]):
            args += ['--network-alias', alias]
    policy = previous['HostConfig']['RestartPolicy']
    restart = policy['Name']
    if restart == 'on-failure' and policy.get('MaximumRetryCount'):
        restart += ':' + str(policy['MaximumRetryCount'])
    args += ['--restart', restart or 'no']
    for port, bindings in previous['HostConfig'].get('PortBindings', {}).items():
        for binding in bindings or []:
            host = binding.get('HostIp', '')
            if ':' in host and not host.startswith('['):
                host = '[' + host + ']'
            args += ['-p', (host + ':' if host else '') + binding['HostPort'] + ':' + port]
    for mount in previous.get('Mounts', []):
        if mount['Type'] not in ('bind', 'volume'):
            raise RuntimeError('Unsupported deployment mount')
        source = mount['Name'] if mount['Type'] == 'volume' else mount['Source']
        args += ['-v', source + ':' + mount['Destination'] + ('' if mount['RW'] else ':ro')]
    for value in previous['Config'].get('Env', []):
        args += ['-e', value]  # Preserve opaque deployment settings; never print their values.
    for key, value in (previous['Config'].get('Labels') or {}).items():
        args += ['--label', key + '=' + value]
    for host in previous['HostConfig'].get('ExtraHosts') or []:
        args += ['--add-host', host]
    if previous['Config'].get('User'):
        args += ['--user', previous['Config']['User']]
    if previous['Config'].get('WorkingDir'):
        args += ['--workdir', previous['Config']['WorkingDir']]
    return args + [image, *(previous['Config'].get('Cmd') or [])]


def require_standard_deployment(previous):
    host = previous['HostConfig']
    for key in ('Privileged', 'ReadonlyRootfs', 'AutoRemove', 'PublishAllPorts', 'Dns', 'DnsOptions', 'DnsSearch',
                'CapAdd', 'CapDrop', 'SecurityOpt', 'Devices', 'DeviceRequests', 'Tmpfs', 'VolumesFrom',
                'Links', 'Ulimits', 'UsernsMode', 'PidMode', 'UTSMode', 'Memory', 'MemoryReservation',
                'NanoCpus', 'CpuShares', 'CpusetCpus', 'CpusetMems', 'OomKillDisable', 'Init'):
        if host.get(key):
            raise RuntimeError('Deployment has a custom setting requiring an explicit preservation rule: ' + key)
    if host.get('CpuQuota') not in (None, 0, -1) or host.get('PidsLimit') not in (None, 0, -1):
        raise RuntimeError('Deployment resource limits require an explicit preservation rule')
    if host.get('IpcMode') not in (None, '', 'private') or host.get('CgroupnsMode') not in (None, '', 'private'):
        raise RuntimeError('Deployment namespaces differ from the reviewed standard container')
    log = host.get('LogConfig') or {}
    if log.get('Type') not in (None, '', 'json-file') or log.get('Config'):
        raise RuntimeError('Deployment logging requires an explicit preservation rule')
    for network in previous['NetworkSettings']['Networks'].values():
        if network.get('IPAMConfig') or network.get('DriverOpts') or network.get('Links'):
            raise RuntimeError('Static network settings require an explicit preservation rule')
    for mount in previous.get('Mounts', []):
        if mount['Destination'] != '/data' and not mount['Destination'].startswith('/data/'):
            raise RuntimeError('Persistent content outside /data requires an additional backup rule')
    hostname = previous['Config'].get('Hostname')
    if hostname and hostname != previous['Id'][:12]:
        raise RuntimeError('A custom hostname requires an explicit preservation rule')
    if previous['Config'].get('Domainname'):
        raise RuntimeError('A custom domain name requires an explicit preservation rule')


def anonymous_health():
    deadline = time.monotonic() + 100
    while time.monotonic() < deadline:
        try:
            value = json.loads(docker('exec', LIVE, 'curl', '--silent', '--fail', '--max-time', '3',
                                      'http://127.0.0.1:18084/captchaImage'))
            if value.get('code') == 200:
                break
        except Exception:
            pass
        time.sleep(1)
    else:
        raise RuntimeError('Anonymous backend health did not pass')
    results = {}
    for path in ('/api/admin/v1/state', '/api/guardian/v1/mobile/context?siteId=site-1'):
        code = docker('exec', LIVE, 'curl', '--silent', '--max-time', '5', '--output', '/dev/null',
                      '--write-out', '%{http_code}', 'http://127.0.0.1:18084' + path).decode()
        results[path] = int(code)
        if code != '401':
            raise RuntimeError('Anonymous protected request did not require authentication')
    return results


def restore_compatible(previous, retained, failed):
    try:
        current = inspect(LIVE)
    except RuntimeError:
        current = None
    if current is not None and current['Id'] != previous['Id']:
        docker('stop', '--time', '30', LIVE)
        docker('rename', LIVE, failed)
        current = None
    if current is None:
        if inspect(retained)['Id'] != previous['Id']:
            raise RuntimeError('Retained predecessor identity changed; no database restoration attempted')
        docker('rename', retained, LIVE)
    docker('start', LIVE)
    anonymous_health()


def recover_after_failure(previous, retained, failed, directory, record, error):
    def best_effort_receipt():
        try:
            write_json(directory / 'receipt.json', record)
        except OSError:
            pass  # Backup disk failure must never prevent restoring the running service.
    record.update(status='recovering-compatible-predecessor', failureType=type(error).__name__)
    best_effort_receipt()
    try:
        restore_compatible(previous, retained, failed)
    except Exception as recovery_error:
        record.update(status='compatible-recovery-incomplete', recoveryFailureType=type(recovery_error).__name__)
        best_effort_receipt()
        raise RuntimeError('Patch and compatible recovery did not complete; current SQL remains untouched. Inspect container state before any further action.') from None
    record.update(status='compatible-predecessor-restored', recoveredAt=now())
    try:
        record['afterRecovery'] = snapshot()
    except Exception:
        record['recoveryReconciliation'] = 'unavailable; service health passed'
    best_effort_receipt()


def patch(evidence_directory, release_directory):
    evidence_directory = pathlib.Path(evidence_directory).resolve()
    release_directory = pathlib.Path(release_directory).resolve()
    if evidence_directory.parent != BUILD or release_directory.parent != BUILD:
        raise RuntimeError('Expected direct workspace build directories')
    evidence = read_json(evidence_directory / 'qa-anonymous-smoke.json')
    if not evidence.get('passed') or evidence.get('loginAttempted') or not evidence.get('dailyContainerUnchanged'):
        raise RuntimeError('Credential-free isolated QA evidence is missing')
    target = inspect(evidence['imageId'])
    receipt = read_json(release_directory / 'release.json')
    previous = inspect(LIVE)
    if not previous['State']['Running'] or previous['Image'] != receipt['newImageId']:
        raise RuntimeError('Daily backend does not match the previous compatible release')
    if target['Config']['Entrypoint'] != previous['Config']['Entrypoint']:
        raise RuntimeError('Image entrypoint changed beyond this compatible patch')
    require_standard_deployment(previous)
    before = snapshot()
    if before['mode'] != 'ACTIVE' or before['namespaces'] != 'guardian,media':
        raise RuntimeError('Current SQL business storage must be initialized and ACTIVE')
    stamp = dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ').lower()
    directory = evidence_directory / ('deployment-' + stamp)
    ignored = subprocess.run(['git', 'check-ignore', '-q', str(directory / 'deployment.private.json')],
                             cwd=ROOT, capture_output=True)
    if ignored.returncode:
        raise RuntimeError('Deployment backup destination is not ignored by Git')
    directory.mkdir()
    retained, failed = 'melhat-before-container-patch-' + stamp, 'melhat-failed-container-patch-' + stamp
    record = {'startedAt': now(), 'status': 'preparing', 'oldImageId': previous['Image'],
              'imageId': target['Id'], 'jarSha256': evidence['jarSha256'], 'backupDirectory': str(directory),
              'retainedContainer': retained, 'before': before, 'applicationCredentialsUsed': False,
              'authenticatedApiCalls': False, 'maintenanceWrites': False, 'cleanupPerformed': False,
              'databaseRestored': False}
    write_json(directory / 'deployment.private.json', previous)
    write_json(directory / 'receipt.json', record)
    # Stop the only daily business writer before the final consistent SQL/data backup.
    try:
        docker('stop', '--time', '30', LIVE)
        if inspect(LIVE)['State']['Running']:
            raise RuntimeError('Daily writer did not stop')
        stopped = snapshot()
        write_json(directory / 'stopped-state.json', stopped)
        with (directory / 'database.sql').open('wb') as output:
            docker('exec', MYSQL, 'sh', '-c',
                   'exec mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --single-transaction --skip-lock-tables --hex-blob --default-character-set=utf8mb4 "$1"',
                   'wearable-container-patch', DATABASE, output=output, timeout=600)
        with (directory / 'backend-data.tar').open('wb') as output:
            docker('cp', LIVE + ':/data', '-', output=output, timeout=600)
        record.update(status='backed-up', stopped=stopped,
                      databaseSha256=hashlib.sha256((directory / 'database.sql').read_bytes()).hexdigest())
        write_json(directory / 'receipt.json', record)
        docker('rename', LIVE, retained)
        docker(*recreate_args(previous, target['Id']))
        health = anonymous_health()
        current = inspect(LIVE)
        if sorted(current['Config'].get('Env', [])) != sorted(previous['Config'].get('Env', [])):
            raise RuntimeError('Opaque deployment environment changed')
        jar = docker('exec', LIVE, 'sha256sum', '/app/fdc-admin.jar').decode().split()[0]
        if jar.lower() != evidence['jarSha256'].lower():
            raise RuntimeError('Running JAR does not match isolated QA')
        deadline = time.monotonic() + 90
        while read_sql('SELECT COUNT(*) FROM wearable_device_report WHERE processed_at IS NULL AND sequence<=' + str(int(stopped['reportWatermark']))) != '0':
            if time.monotonic() >= deadline:
                raise RuntimeError('Existing raw reports have not replayed through the stopped watermark')
            time.sleep(1)
        after = snapshot()
        verify_preservation(stopped, after)
        record.update(status='deployed', completedAt=now(), after=after,
                      anonymousProtectedRequests=health, currentContainerId=current['Id'],
                      replayedThrough=stopped['reportWatermark'])
        receipt.update(newImageId=target['Id'], newContainerId=current['Id'],
                       containerPatchReceipt=str(directory / 'receipt.json'))
        write_json(release_directory / 'release.json', receipt)
    except Exception as error:
        recover_after_failure(previous, retained, failed, directory, record, error)
        raise RuntimeError('Patch failed; prior compatible backend restored against current SQL. See private deployment receipt.') from None
    write_json(directory / 'receipt.json', record)
    return record


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence-directory', required=True)
    parser.add_argument('--release-directory', required=True)
    args = parser.parse_args()
    try:
        print(json.dumps(patch(args.evidence_directory, args.release_directory), ensure_ascii=False))
    except (RuntimeError, ValueError, OSError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
