"""Exercise only a strictly isolated wearable stage; never contacts a physical device."""
import importlib.util
import json
import pathlib
import shutil
import sys
import time
import urllib.error
import urllib.request
import urllib.parse
import uuid

spec = importlib.util.spec_from_file_location('release', pathlib.Path(__file__).with_name('wearable-business-release.py'))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)
BASE = 'http://127.0.0.1:18085'
STAGE_CONTAINER = None


def request(path, token=None, body=None, method=None):
    if STAGE_CONTAINER:
        # curl receives secrets only on stdin. The internal Docker network remains closed.
        config = ['url = "http://127.0.0.1:18084' + path + '"', 'silent', 'show-error', 'max-time = 40',
                  'request = "' + (method or ('POST' if body is not None else 'GET')) + '"',
                  'header = "Content-Type: application/json"', 'write-out = "\\n%{http_code}"']
        if token:
            config.append('header = ' + json.dumps('X-Wearable-Token: ' + token))
        if body is not None:
            config.append('data = ' + json.dumps(release.encode(body), ensure_ascii=False))
        response = release.run('exec', '-i', STAGE_CONTAINER, 'curl', '--config', '-',
                               data=('\n'.join(config) + '\n').encode('utf-8')).decode('utf-8')
        raw, status = response.rsplit('\n', 1)
        if not status.startswith('2'):
            raise RuntimeError('Isolated API returned HTTP ' + status + ' for ' + path.split('?')[0])
        return json.loads(raw)
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['X-Wearable-Token'] = token
    data = None if body is None else release.encode(body).encode('utf-8')
    req = urllib.request.Request(BASE + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=40) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        # Do not expose a credential-bearing request or response body in console errors.
        raise RuntimeError('Isolated API returned HTTP ' + str(error.code) + ' for ' + path.split('?')[0]) from None


def credentials():
    path = release.WORKSPACE / 'output/device-ready/本地联调账号.md'
    rows = [[cell.strip().strip('`') for cell in line.strip().strip('|').split('|')]
            for line in path.read_text(encoding='utf-8-sig').splitlines() if line.strip().startswith('|')]
    header = next(row for row in rows if '用途' in row and '账号' in row and '密码' in row)
    accounts = [row for row in rows if len(row) == len(header) and row[header.index('用途')].endswith('系统管理员')]
    if len(accounts) != 1:
        raise RuntimeError('Expected one documented local administrator login')
    return accounts[0][header.index('账号')], accounts[0][header.index('密码')]


def verify_isolation(folder, stage):
    expected = 'wearable-qa-' + folder.name.removeprefix('wearable-release-')
    if stage['network'] != expected or not stage.get('ready'):
        raise RuntimeError('Stage not ready or unexpected network')
    network = json.loads(release.run('network', 'inspect', expected))[0]
    if not network.get('Internal'):
        raise RuntimeError('Stage must have no external network route')
    for kind in ('mysql', 'redis', 'backend'):
        if stage[kind] != expected + '-' + kind:
            raise RuntimeError('Unexpected isolated container name')
        container = release.inspect(stage[kind])
        if container['Config'].get('Labels', {}).get('wearable.release') != folder.name:
            raise RuntimeError('Container release ownership mismatch')
        if set(container['NetworkSettings']['Networks']) != {expected}:
            raise RuntimeError('Stage container has an unexpected network')
    backend = release.inspect(stage['backend'])
    ports = backend['HostConfig']['PortBindings']
    if ports != {'18084/tcp': [{'HostIp': '127.0.0.1', 'HostPort': '18085'}]}:
        raise RuntimeError('Unexpected stage listener')
    args = dict(arg.split('=', 1) for arg in backend['Config']['Cmd'] if '=' in arg)
    for setting in ('melhat.direct.enabled', 'melhat.belt.enabled', 'melhat.helmet-media.enabled', 'melhat.demo-mode', 'spring.quartz.auto-startup'):
        if args.get('--' + setting) != 'false':
            raise RuntimeError('External integration or seed must be disabled in stage')
    if backend['Image'] != stage['imageId']:
        raise RuntimeError('Stage image identity changed')
    return backend


def pause(token):
    request('/api/admin/v1/maintenance', token, {'mode': 'PAUSED'})
    state = request('/api/admin/v1/maintenance', token)
    if not state.get('paused') or not state.get('quiescent') or state.get('activeWrites') != 0:
        raise RuntimeError('Isolated business writes did not drain')
    return state


def snapshots(tokens):
    states = {
        'admin': request('/api/admin/v1/state', tokens['admin'])['state'],
        'portal': request('/api/guardian/v1/snapshot', tokens['portal'])['state'],
        'mobile': request('/api/guardian/v1/mobile/context?siteId=site-1', tokens['mobile']),
    }
    query = request('/api/admin/v1/query', tokens['admin'], {'kind': 'devices', 'input': {'siteId': 'site-1', 'pageNum': 1, 'pageSize': 50}})['data']
    if {row['id'] for row in query['rows']} != {row['id'] for row in states['admin']['devices']}:
        raise RuntimeError('Administrative device query differs from its visible inventory')
    return states


def inventory(states, visible, people):
    summary = {}
    for client, state in states.items():
        expected = (release.LEDGER_IDS if client == 'admin' else release.DEVICE_IDS) - (set() if visible else {'RL-W001'})
        if {row['id'] for row in state['devices']} != expected:
            raise RuntimeError(client + ' did not show the expected device inventory')
        expected_people = {row['id'] for row in people[client] if visible or row.get('source') != 'DEMO_WATCH'}
        if {row['id'] for row in state['people']} != expected_people:
            raise RuntimeError(client + ' did not apply the simulated identity visibility policy')
        summary[client] = {'devices': len(state['devices']), 'people': len(state['people'])}
    return summary


def device_history(token, state):
    evidence = {}
    for device in sorted(release.REAL_DEVICES):
        point = next(row for row in state['locations'] if row.get('deviceId') == device)
        stamp = release.dt.datetime.fromisoformat(point['time'].replace('Z', '+00:00'))
        if stamp.tzinfo is None:
            stamp = stamp.replace(tzinfo=release.dt.timezone(release.dt.timedelta(hours=8)))
        start = stamp.astimezone(release.dt.timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
        query = {'deviceId': device, 'from': start.isoformat(),
                 'to': (start + release.dt.timedelta(days=1)).isoformat(), 'limit': 1}
        first = request('/api/guardian/v1/locations/history?' + urllib.parse.urlencode(query), token)
        if not first.get('rows') or first['rows'][0].get('deviceId') != device:
            raise RuntimeError('Retained real device history is not readable through its scoped endpoint')
        paged = False
        if first.get('nextCursor'):
            query['cursor'] = first['nextCursor']
            following = request('/api/guardian/v1/locations/history?' + urllib.parse.urlencode(query), token)
            if not following.get('rows') or following['rows'][0]['id'] == first['rows'][0]['id']:
                raise RuntimeError('Device history cursor did not advance to a retained observation')
            paged = True
        evidence[device] = {'firstPageNonempty': True, 'cursorAdvanced': paged, 'date': start.date().isoformat()}
    return evidence


def main(folder):
    global STAGE_CONTAINER
    folder = release.safe_folder(folder)
    stage = release.read_json(folder / 'stage.json')
    backend = verify_isolation(folder, stage)
    STAGE_CONTAINER = stage['backend']
    directory = folder / ('acceptance-' + uuid.uuid4().hex[:8])
    directory.mkdir()
    evidence = {'startedAt': release.now(), 'imageId': backend['Image'], 'isolated': True}
    release.write_json(directory / 'result.json', evidence)
    account, password = credentials()
    tokens = {}
    for client, endpoint, field in (('admin', '/api/admin/v1/login', 'username'),
                                    ('portal', '/api/guardian/v1/login', 'account'),
                                    ('mobile', '/api/guardian/v1/mobile/login', 'account')):
        tokens[client] = request(endpoint, body={field: account, 'password': password})['token']
    release.write_json(directory / 'tokens.private.json', tokens)
    admin = tokens['admin']
    cfg = request('/api/admin/v1/business-config', admin)
    original_visibility = cfg['simulatedWatchVisible']
    request('/api/admin/v1/business-config', admin, {'simulatedWatchVisible': True, 'expectedVersion': cfg['version']}, 'PATCH')
    shown = snapshots(tokens)
    people = {client: state['people'] for client, state in shown.items()}
    evidence['watchVisible'] = inventory(shown, True, people)
    cfg = request('/api/admin/v1/business-config', admin)
    request('/api/admin/v1/business-config', admin, {'simulatedWatchVisible': False, 'expectedVersion': cfg['version']}, 'PATCH')
    evidence['watchHidden'] = inventory(snapshots(tokens), False, people)
    if release.table_counts(stage['mysql'], ['wearable_device'])['wearable_device'] != 3:
        raise RuntimeError('Visibility switch modified the persistent device inventory')
    cfg = request('/api/admin/v1/business-config', admin)
    request('/api/admin/v1/business-config', admin, {'simulatedWatchVisible': original_visibility, 'expectedVersion': cfg['version']}, 'PATCH')
    evidence['maintenanceBefore'] = pause(admin)
    key = release.read_json(folder / 'baseline/business-keys.private.json')['MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY']
    export_dir = directory / 'before-pending-export'
    manifest = release.business_cli(stage['imageId'], backend, key, export_dir, 'Export', require_drained=False)
    state = release.read_json(export_dir / 'guardian-state.json')
    evidence['deviceHistoryQueries'] = device_history(tokens['portal'], state)
    before_counts = {name: len(state.get(name, [])) for name in ('works', 'media', 'groups', 'fences', 'mapAreas', 'devices', 'events', 'locations')}
    if any(before_counts[name] for name in ('works', 'media', 'groups', 'fences', 'mapAreas')):
        raise RuntimeError('Cleaned empty business collections unexpectedly contain seed data')
    # Fixture is inserted ONLY after exact network/container guards above. It cannot reach real devices.
    belt = next(row for row in state['devices'] if row['id'] == '866652023095053')
    stamp, receipt = release.now(), 'QA-REPLAY-' + uuid.uuid4().hex
    payload = {'raw': {'qaFixture': True}, 'context': {'device': belt, 'person': None, 'personId': '',
               'personName': '未关联人员', 'station': belt['station'], 'siteId': belt['siteId'], 'areaId': belt.get('areaId')},
               'status': {'battery': 87, 'online': False, 'lastSeenAt': stamp, 'telemetryReportedAt': stamp,
                          'freshness': 'STALE', 'telemetryFreshness': 'STALE', 'locationFreshness': 'UNKNOWN'},
               'timestamp': stamp, 'rawType': None, 'sos': False}
    statement = 'INSERT INTO wearable_device_report(receipt_id,protocol,device_id,received_at,body) VALUES(' + ','.join([
        release.quote(receipt), release.quote('direct-belt'), release.quote(belt['id']), str(int(time.time() * 1000)), release.quote(release.encode(payload))]) + ');'
    release.sql(stage['mysql'], statement)
    paused = request('/api/admin/v1/maintenance', admin)
    if int(paused['lastSequence']) <= int(manifest['reportWatermark']) or int(paused['pendingReports']) < 1:
        raise RuntimeError('Paused receive journal did not retain the QA report')
    import_dir = directory / 'same-state-import'
    shutil.copytree(export_dir, import_dir)
    imported = release.business_cli(stage['imageId'], backend, key, import_dir, 'Import')
    if not imported.get('maintenancePaused') or int(imported['pendingReports']) < 1 or int(imported['reportWatermark']) <= int(imported['exportReportWatermark']):
        raise RuntimeError('Paused import failed to preserve post-export reports')
    evidence['pausedImport'] = imported
    release.run('restart', '--time', '30', stage['backend'])
    release.healthy(18085, stage['backend'])
    restarted = request('/api/admin/v1/maintenance', admin)
    if not restarted.get('paused') or int(restarted['pendingReports']) < 1:
        raise RuntimeError('Maintenance pause or pending receipt did not survive restart')
    after = snapshots(tokens)
    inventory(after, original_visibility, people)
    restarted_export = directory / 'after-restart-export'
    release.business_cli(stage['imageId'], release.inspect(stage['backend']), key, restarted_export, 'Export', require_drained=False)
    restarted_state = release.read_json(restarted_export / 'guardian-state.json')
    for name in ('works', 'media', 'groups', 'fences', 'mapAreas', 'devices', 'events', 'locations'):
        if len(restarted_state.get(name, [])) != before_counts[name]:
            raise RuntimeError('Restart changed cleaned collection ' + name)
    evidence['restartWithoutReseed'] = before_counts
    request('/api/admin/v1/maintenance', admin, {'mode': 'ACTIVE'})
    deadline = time.monotonic() + 40
    query = 'SELECT COUNT(*) FROM wearable_device_report WHERE receipt_id=' + release.quote(receipt) + ' AND processed_at IS NOT NULL;'
    while release.sql(stage['mysql'], query).strip() != b'1':
        if time.monotonic() >= deadline:
            raise RuntimeError('Pending isolated report did not replay after resume')
        time.sleep(1)
    final_export = directory / 'after-replay-export'
    final = release.business_cli(stage['imageId'], release.inspect(stage['backend']), key, final_export, 'Export')
    current = release.read_json(final_export / 'guardian-state.json')
    stored_belt = next(row for row in current['devices'] if row['id'] == belt['id'])
    # Live connection fields are deliberately projected offline by the disabled gateway.
    # The persisted receive-time observation remains as proof that replay applied this frame.
    if stored_belt.get('telemetryReportedAt') != stamp:
        raise RuntimeError('Receipt marked processed without updating current SQL business state')
    if len(current['events']) != before_counts['events'] or len(current['locations']) != before_counts['locations']:
        raise RuntimeError('QA status report changed retained event or location history')
    evidence.update(completedAt=release.now(), passed=True, replayReceipt=receipt,
                    replayedReportWatermark=final['reportWatermark'], pendingReports=final['pendingReports'],
                    latestExportContainsNewReport=True)
    release.write_json(directory / 'result.json', evidence)
    stage.update(acceptanceVerified=True, acceptanceDirectory=directory.name, acceptanceImageId=backend['Image'],
                 acceptanceToolSha256=release.script_hash('verify-wearable-business-stage.py'))
    release.write_json(folder / 'stage.json', stage)
    print(release.encode(evidence))


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    sys.stderr.reconfigure(encoding='utf-8')
    try:
        if len(sys.argv) != 2:
            raise RuntimeError('Usage: verify-wearable-business-stage.py <release-folder>')
        main(sys.argv[1])
    except (RuntimeError, ValueError, OSError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
