"""Back up, rehearse and release the three-device business cleanup.

Secrets and original records stay in ignored build/wearable-release-* directories.
Preview reads live services; stage writes only separately named, isolated containers.
Release uses a compatible upgrade followed by online maintenance; stage never changes daily services.
"""
import argparse
import base64
import copy
import datetime as dt
import hashlib
import json
import pathlib
import re
import secrets
import shutil
import subprocess
import sys
import tarfile
import time
import urllib.request
import urllib.error
import urllib.parse

ROOT = pathlib.Path(__file__).resolve().parents[1]
WORKSPACE = ROOT.parents[1]
BUILD = ROOT / 'build'
DB = 'new-helmet'
LIVE = 'melhat-backend'
MYSQL = 'melhat-mysql'
REAL_DEVICES = {'866652021714127', '866652023095053'}
DEVICE_IDS = REAL_DEVICES | {'RL-W001'}
LEDGER_IDS = {'device-12', 'device-13', 'RL-W001'}
STATE_FILES = ('guardian-state.json', 'helmet-media-private.json')
SEED_DIR = ROOT / 'ruoyi-admin/src/main/resources'
ARRAY_TABLES = {
    'sites': 'wearable_site', 'organizations': 'wearable_organization', 'areas': 'wearable_area',
    'people': 'wearable_person', 'accounts': 'wearable_account', 'roles': 'wearable_role',
    'dutyShifts': 'wearable_duty_shift', 'devices': 'wearable_device',
    'assignments': 'wearable_assignment', 'history': 'wearable_assignment_history', 'audit': 'wearable_audit',
}


def now():
    return dt.datetime.now(dt.timezone.utc).isoformat()


def encode(value):
    return json.dumps(value, ensure_ascii=False, separators=(',', ':'))


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')


def script_hash(name='wearable-business-release.py'):
    return hashlib.sha256(pathlib.Path(__file__).with_name(name).read_bytes()).hexdigest()


def run(*args, data=None, timeout=120):
    result = subprocess.run(['docker', *args], input=data, capture_output=True, timeout=timeout)
    if result.returncode:
        # Docker errors can contain environment secrets or SQL payloads.
        raise RuntimeError('Docker operation failed: ' + args[0])
    return result.stdout


def inspect(name):
    return json.loads(run('inspect', name))[0]


def sql(container, statement, database=DB):
    # SQL travels on stdin; credentials expand only inside the container.
    return run('exec', '-i', container, 'sh', '-c',
               'exec mysql --default-character-set=utf8mb4 -uroot -p"$MYSQL_ROOT_PASSWORD" -N -B "$1"',
               'wearable-release', database, data=statement.encode('utf-8'), timeout=600)


def dump(container=MYSQL):
    return run('exec', container, 'sh', '-c',
               'exec mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --single-transaction --skip-lock-tables '
               '--skip-extended-insert --complete-insert --hex-blob --default-character-set=utf8mb4 "$1"',
               'wearable-release', DB)


def quote(value):
    """Hex string literal avoids shell, SQL quoting and Unicode ambiguities."""
    return 'CONVERT(0x' + str(value).encode('utf-8').hex() + ' USING utf8mb4) COLLATE utf8mb4_unicode_ci' if str(value) else "'' COLLATE utf8mb4_unicode_ci"


def identifier(value):
    if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', value):
        raise ValueError('Unsafe SQL identifier')
    return '`' + value + '`'


def dump_counts(data):
    counts = {name.decode(): 0 for name in re.findall(rb'^CREATE TABLE `([^`]+)`', data, re.M)}
    for name in re.findall(rb'^INSERT INTO `([^`]+)`', data, re.M):
        counts[name.decode()] += 1
    if not counts or 'wearable_device' not in counts:
        raise RuntimeError('Backup does not contain wearable tables')
    return counts


def table_counts(container, names):
    query = '\nUNION ALL\n'.join('SELECT ' + quote(name) + ',COUNT(*) FROM ' + identifier(name) for name in names) + ';'
    return {line.split('\t')[0]: int(line.split('\t')[1]) for line in sql(container, query).decode().splitlines()}


def safe_folder(value):
    folder = pathlib.Path(value).resolve()
    if folder.parent != BUILD.resolve() or not re.fullmatch(r'wearable-release-\d{8}t\d{6}z-[a-f0-9]{6}', folder.name):
        raise RuntimeError('Expected this workspace build/wearable-release-* directory')
    return folder


def replace_env_key(content, key):
    if len(base64.b64decode(key, validate=True)) != 32:
        raise RuntimeError('Media key must decode to 32 bytes')
    name = 'MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY'
    lines = content.splitlines(keepends=True)
    result, found = [], False
    newline = '\r\n' if '\r\n' in content else '\n'
    for line in lines:
        if re.match(r'^' + name + r'\s*=', line):
            if not found:
                result.append(name + '=' + key + newline)
                found = True
        else:
            result.append(line)
    if not found:
        if result and not result[-1].endswith(('\r', '\n')):
            result[-1] += newline
        result.append(name + '=' + key + newline)
    return ''.join(result)


def persist_local_key(folder):
    folder = safe_folder(folder)
    path = ROOT / 'local-dev/.env'
    if subprocess.run(['git', 'check-ignore', str(path)], cwd=WORKSPACE, capture_output=True).returncode:
        raise RuntimeError('Local environment file is not ignored; refusing to write a secret')
    key = read_json(folder / 'baseline/business-keys.private.json')['MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY']
    original = path.read_bytes()
    backup_path = folder / 'baseline/local-env-before.private'
    if not backup_path.exists():
        backup_path.write_bytes(original)
    content = original.decode('utf-8-sig')
    updated = replace_env_key(content, key)
    prefix = b'\xef\xbb\xbf' if original.startswith(b'\xef\xbb\xbf') else b''
    path.write_bytes(prefix + updated.encode('utf-8'))
    other_before = [line for line in content.splitlines() if not line.startswith('MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY=')]
    other_after = [line for line in updated.splitlines() if not line.startswith('MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY=')]
    if other_before != other_after:
        raise RuntimeError('Unexpected changes outside the media encryption key')
    receipt = {'persisted': True, 'otherSettingsPreserved': True, 'backup': backup_path.name,
               'keyFingerprint': hashlib.sha256(base64.b64decode(key)).hexdigest()}
    write_json(folder / 'local-env-update.json', receipt)
    return receipt


def new_folder():
    stamp = dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ').lower() + '-' + secrets.token_hex(3)
    folder = BUILD / ('wearable-release-' + stamp)
    folder.mkdir(parents=True, exist_ok=False)
    ignored = subprocess.run(['git', 'check-ignore', str(folder)], cwd=WORKSPACE, capture_output=True)
    if ignored.returncode:
        raise RuntimeError('Backup folder is not ignored by Git; no secrets were written')
    return folder, stamp


def seed_rows(kind, key):
    return read_json(SEED_DIR / (kind + '-seed.json')).get(key, [])


def known_seed(row, seeds):
    """A reused ID alone never classifies a changed record as a known seed."""
    return any(row == candidate for candidate in seeds)


def external_placeholder(row, external_references=()):
    return (row.get('deviceId') in REAL_DEVICES and row.get('source') == 'device' and
            re.fullmatch(r'(?:HAT|BELT)-[0-9]+', str(row.get('externalId', ''))) is not None and
            row.get('externalStatus') == '待回传' and
            row.get('id') not in external_references and row.get('externalId') not in external_references and
            not any(row.get(key) for key in ('externalRecordId', 'externalSource', 'externalSystem')))


def external_references(container=MYSQL):
    found = sql(container, "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='new-helmet' AND table_name='external_data_record';")
    if found.strip() != b'1':
        return set()
    references = set()
    for line in sql(container, 'SELECT HEX(body) FROM external_data_record;').decode().splitlines():
        record = json.loads(bytes.fromhex(line).decode())
        references.update(str(record[key]) for key in ('localId', 'externalId') if record.get(key))
    return references


def referenced_ids(value, candidates):
    """Follow nested historical snapshots and member arrays without guessing field names."""
    if isinstance(value, dict):
        return set().union(*(referenced_ids(item, candidates) for item in value.values())) if value else set()
    if isinstance(value, list):
        return set().union(*(referenced_ids(item, candidates) for item in value)) if value else set()
    return {value} if isinstance(value, str) and value in candidates else set()


def prune_guardian(original, seeds=None, external_links=()):
    state = copy.deepcopy(original)
    seeds = seeds if seeds is not None else read_json(SEED_DIR / 'guardian-seed.json')
    archive = []

    def retain(key, predicate, reason):
        rows = state.get(key)
        if not isinstance(rows, list):
            return
        kept = []
        for row in rows:
            if predicate(row):
                kept.append(row)
            else:
                archive.append({'collection': key, 'reason': reason, 'record': row})
        state[key] = kept

    actual = {row.get('id') for row in state.get('devices', [])}
    if not DEVICE_IDS <= actual:
        raise RuntimeError('A required real device or selected simulated watch is absent; refusing replacement')
    retain('devices', lambda row: row.get('id') in DEVICE_IDS, 'outside-three-device-inventory')
    for row in state['devices']:
        if row['id'] == 'RL-W001':
            if row.get('source') not in ('DEMO_WATCH', 'demo', None) or row.get('type') != 'W':
                raise RuntimeError('Selected watch is no longer the known simulated device')
            row.update(source='DEMO_WATCH', demo=True)
    retain('bindings', lambda row: row.get('deviceId') in DEVICE_IDS, 'binding-of-archived-device')
    for key in ('events', 'media', 'works', 'fenceRecords', 'calls', 'broadcasts', 'locations', 'sharedCommunications'):
        retain(key, lambda row, k=key: row.get('deviceId') in REAL_DEVICES or
               (str(row.get('source', '')).lower() in ('device', 'platform', 'manual', 'manual_sos', 'external', 'direct-helmet', 'direct-belt')
                and not known_seed(row, seeds.get(k, []))) or
               (k == 'sharedCommunications' and row.get('deviceId') in REAL_DEVICES),
               'demo-or-unverified-record')
    for event in state.get('events', []):
        if external_placeholder(event, external_links):
            archive.append({'collection': 'eventExternalPlaceholder', 'reason': 'synthetic-external-link-without-record',
                            'record': {key: event.get(key) for key in ('id', 'deviceId', 'externalId', 'externalStatus')}})
            event['externalId'] = ''
            event['externalStatus'] = '未接入外部系统'
    # Only the selected watch's own observations survive. No invented owner binding.
    owners = {row.get('personId') for row in state.get('bindings', [])
              if row.get('deviceId') == 'RL-W001' and not row.get('end') and row.get('personId')}
    if len(owners) != 1:
        raise RuntimeError('Selected simulated watch must have exactly one existing active owner')
    retain('vitals', lambda row: row.get('deviceId') == 'RL-W001' and row.get('personId') in owners or
           str(row.get('source', '')).upper() in ('DEVICE', 'PLATFORM', 'DIRECT_HELMET', 'DIRECT_BELT', 'DIRECT_WATCH'),
           'other-simulated-watch-observation')
    for key in ('groups', 'fences', 'mapAreas'):
        # Unproven polygons/groups are quarantined, not silently accepted as real safety configuration.
        retain(key, lambda row: row.get('source') in ('PLATFORM', 'MANUAL', 'EXTERNAL') and
               not known_seed(row, seeds.get(key, [])), 'unverified-preloaded-configuration')
    value = state.get('sos')
    if isinstance(value, dict) and value and value.get('deviceId') not in REAL_DEVICES:
        archive.append({'collection': 'sos', 'reason': 'unverified-preloaded-transient', 'record': value})
        state['sos'] = {}
    assistance = state.get('assistance')
    real_events = {row['id'] for row in state.get('events', [])}
    if isinstance(assistance, dict) and assistance:
        kept = {}
        # Current assistance is a map keyed by event ID, not one SOS record.
        for key, record in assistance.items():
            if isinstance(record, dict) and (record.get('eventId', key) in real_events or record.get('deviceId') in REAL_DEVICES):
                kept[key] = record
            else:
                archive.append({'collection': 'assistance', 'reason': 'demo-or-unverified-assistance',
                                'record': {'id': key, 'value': record}})
        state['assistance'] = kept
    person_candidates = {row['id'] for row in state.get('people', [])}
    retained = {key: value for key, value in state.items() if key not in ('people', 'stations')}
    referenced = set(owners) | referenced_ids(retained, person_candidates)
    real_retained = copy.deepcopy(retained)
    for key in ('devices', 'bindings', 'vitals'):
        if isinstance(real_retained.get(key), list):
            real_retained[key] = [row for row in real_retained[key]
                                  if row.get('id') != 'RL-W001' and row.get('deviceId') != 'RL-W001']
    real_people = referenced_ids(real_retained, person_candidates)
    retain('people', lambda row: row.get('id') in referenced, 'unreferenced-preloaded-person')
    for row in state.get('people', []):
        if row.get('id') in owners and row.get('id') not in real_people:
            row.update(source='DEMO_WATCH', demo=True, name='手表演示人员')
            # Preserve example vitals, never a drawn map location as a live observation.
            for key in ('position', 'longitude', 'latitude'):
                row.pop(key, None)
            row['locationValid'] = False
    station_ids = {'S1'} | referenced_ids({key: value for key, value in state.items() if key != 'stations'},
                                         {row['id'] for row in state.get('stations', [])})
    retain('stations', lambda row: row.get('id') in station_ids, 'unreferenced-site-without-retained-history')
    for row in state.get('stations', []):
        if row['id'] == 'S1':
            row['name'] = '测试厂区'
    return state, archive


def rows(container, table):
    output = sql(container, 'SELECT HEX(body) FROM ' + identifier(table) + ' ORDER BY sort_order,id;')
    return [json.loads(bytes.fromhex(line).decode('utf-8')) for line in output.decode().splitlines()]


def ledger_snapshot(container):
    state = {key: rows(container, table) for key, table in ARRAY_TABLES.items()}
    revision, next_id = sql(container, 'SELECT revision,next_id FROM wearable_meta WHERE id=1;').decode().strip().split('\t')
    state.update(revision=int(revision), nextId=int(next_id), idempotency={})
    for line in sql(container, 'SELECT HEX(idem_key),HEX(body) FROM wearable_idempotency;').decode().splitlines():
        key, body = line.split('\t')
        state['idempotency'][bytes.fromhex(key).decode()] = json.loads(bytes.fromhex(body).decode())
    for line in sql(container, 'SELECT doc_key,HEX(body) FROM wearable_document;').decode().splitlines():
        key, body = line.split('\t')
        state[key] = json.loads(bytes.fromhex(body).decode('utf-8'))
    return state


def prune_ledger(original, guardian):
    state = copy.deepcopy(original)
    archive = []

    def retain(key, predicate, reason):
        kept = []
        for row in state.get(key, []):
            if predicate(row):
                kept.append(row)
            else:
                archive.append({'collection': key, 'reason': reason, 'record': row})
        state[key] = kept

    if not LEDGER_IDS <= {row.get('id') for row in state.get('devices', [])}:
        raise RuntimeError('Ledger lacks an expected device; no synthetic replacement is allowed')
    retain('devices', lambda row: row.get('id') in LEDGER_IDS, 'outside-three-device-inventory')
    for device in state['devices']:
        if device['id'] == 'RL-W001':
            if device.get('type') != 'WATCH' or device.get('source') not in (None, 'DEMO_WATCH'):
                raise RuntimeError('Ledger selected watch has changed identity')
            device.update(source='DEMO_WATCH', demo=True)
    retain('assignments', lambda row: row.get('deviceId') in LEDGER_IDS, 'assignment-of-archived-device')
    retained_portal_people = {row['id'] for row in guardian.get('people', [])}
    person_ids = {row.get('personId') for row in state.get('assignments', []) if row.get('personId')}
    person_ids |= referenced_ids(state.get('history', []), {row['id'] for row in state.get('people', [])})
    person_ids |= {row['id'] for row in state.get('people', [])
                   if row.get('portalId') in retained_portal_people or row.get('portalPersonId') in retained_portal_people
                   or row['id'] in retained_portal_people}
    retain('people', lambda row: row['id'] in person_ids, 'unreferenced-preloaded-person')
    watch_owners = {row.get('personId') for row in state.get('assignments', [])
                    if row.get('deviceId') == 'RL-W001' and row.get('active') is True}
    if len(watch_owners) != 1:
        raise RuntimeError('Ledger simulated watch ownership is ambiguous')
    for row in state['people']:
        portal_person = next((item for item in guardian.get('people', [])
                              if item['id'] in (row.get('portalId'), row.get('portalPersonId'), row['id'])), None)
        if row['id'] in watch_owners and (portal_person is None or portal_person.get('source') == 'DEMO_WATCH'):
            row.update(source='DEMO_WATCH', demo=True, name='手表演示人员')
    # Existing credentials/roles remain valid; removed sample people stop impersonating operators.
    for account in state.get('accounts', []):
        if account.get('personId') and account['personId'] not in person_ids:
            archive.append({'collection': 'accountAssociation', 'reason': 'archived-sample-person',
                            'record': {'id': account['id'], 'personId': account['personId']}})
            account['personId'] = None
    for shift in state.get('dutyShifts', []):
        if isinstance(shift.get('personIds'), list):
            selected = [value for value in shift['personIds'] if value in person_ids]
            if selected != shift['personIds']:
                archive.append({'collection': 'dutyShiftAssociation', 'reason': 'archived-sample-person', 'record': copy.deepcopy(shift)})
                shift['personIds'] = selected
    # Keep site/organization/area definitions needed for account scopes and retained records.
    referenced_sites = referenced_ids({key: state.get(key, []) for key in ('accounts', 'roles', 'people', 'devices', 'history')},
                                      {row['id'] for row in state.get('sites', [])})
    retain('sites', lambda row: row['id'] in referenced_sites, 'unreferenced-site')
    for row in state['sites']:
        if row['id'] == 'site-1':
            row['name'] = '测试厂区'
    for key in ('maintenanceOrders', 'maintenanceRecords', 'lifecycleHistory', 'groupHistory'):
        retain(key, lambda row: row.get('deviceId') in LEDGER_IDS or row.get('source') in ('PLATFORM', 'EXTERNAL', 'MANUAL'),
               'unverified-preloaded-maintenance')
    for integration in state.get('integrations', []):
        if integration.get('endpointKey') == 'SAMPLE_A':
            integration.update(status='NOT_CONNECTED', attempts=0)
            integration['credential'] = ''
    removed_ids = {row['id'] for key in ('devices', 'people') for row in original.get(key, [])
                   if row['id'] not in {item['id'] for item in state.get(key, [])}}
    def refers_to_removed(value):
        if isinstance(value, dict):
            return any(refers_to_removed(item) for item in value.values())
        if isinstance(value, list):
            return any(refers_to_removed(item) for item in value)
        return isinstance(value, str) and value in removed_ids
    for key, value in list(state.get('idempotency', {}).items()):
        if refers_to_removed(value):
            archive.append({'collection': 'idempotency', 'reason': 'response-for-archived-entity', 'record': {'id': key, 'value': value}})
            del state['idempotency'][key]
    return state, archive


def archive_sql(run_id, collection, record, reason):
    rid = str(record.get('id') or record.get('doc_key') or hashlib.sha256(encode(record).encode()).hexdigest())
    return ('INSERT IGNORE INTO wearable_cleanup_archive(run_id,collection,record_id,reason,body) VALUES (' +
            ','.join(quote(v) for v in (run_id, collection, rid, reason, encode(record))) + ');')


def ledger_cleanup_sql(before, after, archive, run_id):
    statements = ['CREATE TABLE IF NOT EXISTS wearable_cleanup_archive ('
                  'run_id VARCHAR(64) NOT NULL,collection VARCHAR(64) NOT NULL,record_id VARCHAR(192) NOT NULL,'
                  'reason VARCHAR(128) NOT NULL,body LONGTEXT NOT NULL,archived_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,'
                  'PRIMARY KEY(run_id,collection,record_id));', 'START TRANSACTION;']
    for entry in archive:
        statements.append(archive_sql(run_id, entry['collection'], entry['record'], entry['reason']))
    # Delete only IDs observed in this snapshot, never a NOT IN sweep which could catch new registrations.
    for key, table in ARRAY_TABLES.items():
        kept = {row['id']: row for row in after.get(key, [])}
        for old in before.get(key, []):
            if old['id'] not in kept:
                statements.append('DELETE FROM ' + identifier(table) + ' WHERE id=' + quote(old['id']) +
                                  ' AND body=' + quote(encode(old)) + ';')
            elif old != kept[old['id']]:
                changed = kept[old['id']]
                fields = ['body=' + quote(encode(changed))]
                if key in ('sites', 'people'):
                    fields.append('name=' + quote(changed.get('name', '')))
                if key == 'accounts':
                    fields.append('person_id=' + ('NULL' if changed.get('personId') is None else quote(changed['personId'])))
                statements.append('UPDATE ' + identifier(table) + ' SET ' + ','.join(fields) + ' WHERE id=' + quote(old['id']) + ';')
    for key in after:
        if key not in ARRAY_TABLES and key not in ('revision', 'nextId', 'idempotency') and after[key] != before.get(key):
            statements.append('UPDATE wearable_document SET body=' + quote(encode(after[key])) + ' WHERE doc_key=' + quote(key) + ';')
    for key in before.get('idempotency', {}):
        if key not in after.get('idempotency', {}):
            statements.append('DELETE FROM wearable_idempotency WHERE idem_key=' + quote(key) + ';')
    statements.append('INSERT IGNORE INTO wearable_cleanup_archive(run_id,collection,record_id,reason,body) SELECT ' +
                      quote(run_id) + ",'admin_ledger','1','legacy-snapshot',body FROM admin_ledger WHERE id=1;")
    statements.append('UPDATE admin_ledger SET body=' + quote(encode(after)) + ' WHERE id=1;')
    statements.append('UPDATE wearable_meta SET revision=revision+1 WHERE id=1;')
    statements.append('COMMIT;')
    return '\n'.join(statements)


LEGACY_DEMO_TABLES = ('safety_hat_location_record', 'electronic_fence_latitude', 'electronic_fence_alarm',
                      'real_time_alarm', 'sos_alarm_record', 'file_record', 'intercom_record',
                      'tts_text_synthesis_broadcast', 'safety_hat_info', 'electronic_fence', 'group_info', 'demo_compat_record')


def legacy_columns(container):
    query = 'SELECT table_name,column_name FROM information_schema.columns WHERE table_schema=' + quote(DB) + ' ORDER BY table_name,ordinal_position;'
    result = {}
    for line in sql(container, query).decode().splitlines():
        table, column = line.split('\t')
        if table in LEGACY_DEMO_TABLES:
            result.setdefault(table, []).append(column)
    return result


def old_demo_cleanup_sql(run_id, columns, removed_device_codes):
    """Match the original seed's explicit provenance; preserve unknown/real histories."""
    statements = ['START TRANSACTION;']
    for table in LEGACY_DEMO_TABLES:
        if table not in columns:
            continue
        fields = columns[table]
        condition = "create_by='demo'"
        if table == 'demo_compat_record':
            condition = "module_key IN ('space','module','headBand','systemHat') AND business_key LIKE 'demo-%' AND JSON_EXTRACT(payload,'$.demo')=true"
        if table == 'safety_hat_info' and removed_device_codes:
            condition = '(' + condition + " OR (create_by='guardian' AND hat_number IN (" + ','.join(quote(code) for code in sorted(removed_device_codes)) + ')))'
        if 'hat_number' in fields:
            for device in sorted(REAL_DEVICES):
                condition += ' AND LOCATE(' + quote(device) + ',COALESCE(hat_number,\'\'))=0'
        body = 'JSON_OBJECT(' + ','.join(quote(field) + ',' + identifier(field) for field in fields) + ')'
        statements.append('INSERT IGNORE INTO wearable_cleanup_archive(run_id,collection,record_id,reason,body) '
                          'SELECT ' + quote(run_id) + ',' + quote(table) + ',CAST(id AS CHAR),'
                          "'legacy-explicit-demo'," + body + ' FROM ' + identifier(table) + ' WHERE ' + condition + ';')
        statements.append('DELETE FROM ' + identifier(table) + ' WHERE ' + condition + ';')
    statements.append('COMMIT;')
    return '\n'.join(statements)


def backup(folder):
    private = folder / 'baseline'
    private.mkdir(exist_ok=False)
    live = inspect(LIVE)
    if live['Name'] != '/' + LIVE or not live['State']['Running']:
        raise RuntimeError('Expected running daily backend')
    write_json(private / 'container.private.json', live)
    write_json(private / 'mysql-container.private.json', inspect(MYSQL))
    write_json(private / 'redis-container.private.json', inspect('melhat-redis'))
    live_env = dict(value.split('=', 1) for value in live['Config'].get('Env', []) if '=' in value)
    media_key = live_env.get('MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY') or base64.b64encode(secrets.token_bytes(32)).decode('ascii')
    if len(base64.b64decode(media_key, validate=True)) != 32:
        raise RuntimeError('Configured media encryption key is not a valid 32-byte base64 key')
    write_json(private / 'business-keys.private.json', {'MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY': media_key})
    database = dump()
    (private / 'database.sql').write_bytes(database)
    for name in STATE_FILES:
        run('cp', LIVE + ':/data/' + name, str(private / name))
    data_archive = run('exec', LIVE, 'tar', '-C', '/data', '-cf', '-', '.')
    (private / 'backend-data.tar').write_bytes(data_archive)
    with tarfile.open(private / 'backend-data.tar') as archive:
        write_json(private / 'media-file-manifest.private.json', [
            {'name': item.name, 'size': item.size, 'mtime': item.mtime} for item in archive.getmembers() if item.isfile()])
    state_source = 'legacy-file'
    if business_initialized() and current_authority(LIVE).get('mode') != 'legacy-file':
        business_cli(live['Image'], live, media_key, private / 'current-sql-export', 'Export', require_drained=False)
        for name in STATE_FILES:
            exported = private / 'current-sql-export' / name
            if exported.is_file():
                shutil.copy2(exported, private / name)
        state_source = 'current-sql-export'
    # Preserve the exact client artifacts/source metadata without printing paths containing secrets.
    clients = {}
    for key, relative in {'portal': 'pc前台项目', 'admin': 'pc后台项目', 'android': 'android代码/melhat_android-main'}.items():
        root = WORKSPACE / relative
        files = ('package.json', 'vite.config.js', 'vite.config.ts') if key != 'android' else (
            'pubspec.yaml', 'lib/config/backend_config.dart', 'android/app/build.gradle.kts',
            'build/app/outputs/flutter-apk/app-debug.apk')
        artifacts = []
        for relative_file in files:
            source = root / relative_file
            if source.is_file():
                target = private / 'clients' / key / relative_file
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, target)
                artifacts.append({'path': relative_file, 'sha256': hashlib.sha256(source.read_bytes()).hexdigest(), 'bytes': source.stat().st_size})
        clients[key] = artifacts
    write_json(private / 'clients.json', clients)
    diff = subprocess.run(['git', 'diff', '--binary'], cwd=WORKSPACE, capture_output=True)
    (private / 'workspace-diff.private.patch').write_bytes(diff.stdout)
    state = read_json(private / 'guardian-state.json')
    clean, quarantine = prune_guardian(state, external_links=external_references())
    write_json(folder / 'guardian-preview.private.json', clean)
    write_json(folder / 'guardian-quarantine.private.json', quarantine)
    receipt = {'createdAt': now(), 'liveContainerId': live['Id'], 'liveImageId': live['Image'],
               'liveImage': live['Config']['Image'], 'databaseSha256': hashlib.sha256(database).hexdigest(),
               'databaseCounts': dump_counts(database),
               'guardianSha256': hashlib.sha256((private / STATE_FILES[0]).read_bytes()).hexdigest(),
               'dataArchiveSha256': hashlib.sha256(data_archive).hexdigest(),
               'snapshotMode': 'online-read-only-not-a-cross-store-cutover-checkpoint',
               'stateSource': state_source,
               'guardianBefore': {k: len(v) for k, v in state.items() if isinstance(v, list)},
               'guardianAfter': {k: len(v) for k, v in clean.items() if isinstance(v, list)},
               'quarantinedCount': len(quarantine), 'cloudMediaFilesCopied': False,
               'cloudMediaScope': 'reference/index only; cloud assets are not modified by this tool'}
    write_json(folder / 'preview.json', receipt)
    return receipt


def isolated_command(live_command, mysql_name, redis_name, password):
    replacements = {
        '--spring.datasource.druid.master.url': 'jdbc:mysql://' + mysql_name + ':3306/' + DB + '?useUnicode=true&characterEncoding=utf8&useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Shanghai',
        '--spring.datasource.druid.master.username': 'root', '--spring.datasource.druid.master.password': password,
        '--spring.redis.host': redis_name, '--spring.redis.port': '6379', '--spring.redis.database': '0', '--spring.redis.password': '',
        '--spring.quartz.auto-startup': 'false', '--melhat.direct.enabled': 'false', '--melhat.belt.enabled': 'false',
        '--melhat.helmet-media.enabled': 'false', '--melhat.demo-mode': 'false',
    }
    return [arg for arg in live_command if arg.split('=', 1)[0] not in replacements] + [key + '=' + value for key, value in replacements.items()]


def stage(folder, image=None):
    folder = safe_folder(folder)
    preview = read_json(folder / 'preview.json')
    name = 'wearable-qa-' + folder.name.removeprefix('wearable-release-')
    mysql_name, redis_name = name + '-mysql', name + '-redis'
    if (folder / 'stage.json').exists():
        metadata = read_json(folder / 'stage.json')
        password = read_json(folder / 'stage-credentials.private.json')['password']
        clone = inspect(mysql_name)
        if clone['Config'].get('Labels', {}).get('wearable.release') != folder.name:
            raise RuntimeError('Existing stage container does not belong to this release')
        network = json.loads(run('network', 'inspect', name))[0]
        if not network.get('Internal') or set(clone['NetworkSettings']['Networks']) != {name}:
            raise RuntimeError('Existing stage database is not isolated')
        tool_hash = script_hash()
        if metadata.get('cleanupVerified') and metadata.get('cleanupToolSha256') == tool_hash:
            if image and not metadata.get('ready'):
                return start_stage_backend(folder, metadata, image, password)
            return metadata
        if metadata.get('ready'):
            raise RuntimeError('Tool changed after backend acceptance; create a fresh isolated stage')
        # A failed first health check may have left only this private QA writer running.
        # Stop/remove it before restoring; a restore must never race a running writer.
        try:
            backend = inspect(metadata['backend'])
        except RuntimeError:
            backend = None
        if backend is not None:
            if backend['Config'].get('Labels', {}).get('wearable.release') != folder.name \
                    or set(backend['NetworkSettings']['Networks']) != {name}:
                raise RuntimeError('Incomplete stage writer is not owned by this isolated release')
            run('rm', '-f', metadata['backend'])
    else:
        password = secrets.token_urlsafe(32)
        metadata = {'createdAt': now(), 'network': name, 'mysql': mysql_name, 'redis': redis_name,
                    'backend': name + '-backend', 'image': image, 'ready': False, 'restoreVerified': False}
        write_json(folder / 'stage.json', metadata)
        write_json(folder / 'stage-credentials.private.json', {'password': password})
        run('network', 'create', '--internal', '--label', 'wearable.release=' + folder.name, name)
        run('run', '-d', '--name', mysql_name, '--network', name, '--label', 'wearable.release=' + folder.name,
            '-e', 'MYSQL_ROOT_PASSWORD=' + password, '-e', 'MYSQL_DATABASE=' + DB,
            'mysql:8.0', '--character-set-server=utf8mb4', '--collation-server=utf8mb4_unicode_ci',
            '--default-authentication-plugin=mysql_native_password')
    deadline = time.monotonic() + 120
    while True:
        try:
            sql(mysql_name, 'SELECT 1;')
            break
        except RuntimeError:
            if time.monotonic() >= deadline:
                raise RuntimeError('Isolated MySQL did not become ready')
            time.sleep(1)
    baseline = (folder / 'baseline/database.sql').read_bytes()
    if hashlib.sha256(baseline).hexdigest() != preview['databaseSha256']:
        raise RuntimeError('Database backup hash mismatch')
    # This database belongs to the verified private QA container above. Dropping it
    # prevents newly introduced tables/import markers surviving a rehearsal restart.
    sql(mysql_name, 'DROP DATABASE IF EXISTS `new-helmet`; CREATE DATABASE `new-helmet` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;', database='mysql')
    sql(mysql_name, 'SET autocommit=0;\n' + baseline.decode('utf-8') + '\nCOMMIT;')
    restored = table_counts(mysql_name, preview['databaseCounts'])
    if restored != preview['databaseCounts']:
        raise RuntimeError('Restored database row counts do not match its backup')
    metadata['restoreVerified'] = True
    metadata['restoredCounts'] = restored
    write_json(folder / 'stage.json', metadata)
    guardian, archived_guardian = prune_guardian(read_json(folder / 'baseline/guardian-state.json'), external_links=external_references(mysql_name))
    before = ledger_snapshot(mysql_name)
    after, archived_ledger = prune_ledger(before, guardian)
    write_json(folder / 'ledger-before.private.json', before)
    write_json(folder / 'ledger-after.private.json', after)
    write_json(folder / 'ledger-quarantine.private.json', archived_ledger)
    cleanup = ledger_cleanup_sql(before, after, archived_ledger + archived_guardian, folder.name)
    removed_codes = {row.get('portalDeviceId') or row.get('code') or row['id'] for row in before['devices'] if row['id'] not in LEDGER_IDS}
    cleanup += '\n' + old_demo_cleanup_sql(folder.name, legacy_columns(mysql_name), removed_codes)
    (folder / 'cleanup.private.sql').write_text(cleanup, encoding='utf-8')
    sql(mysql_name, cleanup)
    actual = rows(mysql_name, 'wearable_device')
    if {row['id'] for row in actual} != LEDGER_IDS:
        raise RuntimeError('Cleaned ledger is not exactly the expected three devices')
    qa_data = folder / 'qa-data'
    qa_data.mkdir(exist_ok=True)
    write_json(qa_data / 'guardian-state.json', guardian)
    shutil.copy2(folder / 'baseline/helmet-media-private.json', qa_data / 'helmet-media-private.json')
    metadata.update(cleanedCounts=table_counts(mysql_name, preview['databaseCounts']),
                    guardianAfter={k: len(v) for k, v in guardian.items() if isinstance(v, list)},
                    cleanDeviceIds=sorted(row['id'] for row in actual), cleanupVerified=True,
                    cleanupToolSha256=script_hash(), acceptanceVerified=False)
    write_json(folder / 'stage.json', metadata)
    if image:
        return start_stage_backend(folder, metadata, image, password)
    return metadata


def start_stage_backend(folder, metadata, image, password):
    # A host with an isolated Docker bridge may suppress port publishing. Resume a
    # partially completed launch through container loopback, without adding a network.
    try:
        existing = inspect(metadata['backend'])
    except RuntimeError:
        existing = None
    if existing is not None:
        if existing['Config'].get('Labels', {}).get('wearable.release') != folder.name \
                or set(existing['NetworkSettings']['Networks']) != {metadata['network']} \
                or existing['Image'] != inspect(image)['Id']:
            raise RuntimeError('Incomplete stage backend does not match its isolated release')
        healthy(18085, metadata['backend'])
        metadata.update(ready=True, image=image, imageId=existing['Image'])
        write_json(folder / 'stage.json', metadata)
        return metadata
    live = read_json(folder / 'baseline/container.private.json')
    media_key = read_json(folder / 'baseline/business-keys.private.json')['MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY']
    command = isolated_command(live['Config'].get('Cmd') or [], metadata['mysql'], metadata['redis'], password)
    if business_initialized(metadata['mysql']):
        # A restored SQL import marker intentionally ignores JSON files. Apply the cleaned state
        # through the same guarded importer used during a live cutover, before starting a writer.
        connection = {'Config': {'Cmd': command}, 'NetworkSettings': {'Networks': {metadata['network']: {}}}}
        export_directory = folder / 'stage-current-export'
        manifest = business_cli(image, connection, media_key, export_directory, 'Export')
        import_directory = folder / 'stage-clean-import'
        import_directory.mkdir()
        shutil.copy2(folder / 'qa-data/guardian-state.json', import_directory / 'guardian-state.json')
        if read_json(folder / 'preview.json').get('stateSource') == 'legacy-file':
            manifest['importMedia'] = True
            shutil.copy2(folder / 'qa-data/helmet-media-private.json', import_directory / 'helmet-media-private.json')
        write_json(import_directory / 'manifest.json', manifest)
        prepare_offline_import(metadata['mysql'], metadata['backend'], manifest)
        business_cli(image, connection, media_key, import_directory, 'Import')
    try:
        redis = inspect(metadata['redis'])
    except RuntimeError:
        redis = None
    if redis is not None:
        if redis['Config'].get('Labels', {}).get('wearable.release') != folder.name \
                or set(redis['NetworkSettings']['Networks']) != {metadata['network']}:
            raise RuntimeError('Stage Redis does not belong to this isolated release')
    else:
        run('run', '-d', '--name', metadata['redis'], '--network', metadata['network'], '--label', 'wearable.release=' + folder.name, 'redis:7-alpine')
    args = ['run', '-d', '--name', metadata['backend'], '--network', metadata['network'],
                '--label', 'wearable.release=' + folder.name, '-p', '127.0.0.1:18085:18084',
                '-v', str(folder / 'qa-data') + ':/data', '-e', 'TZ=Asia/Shanghai', '-e', 'MELHAT_DEMO_MODE=false',
                '-e', 'MELHAT_DIRECT_ENABLED=false', '-e', 'MELHAT_BELT_ENABLED=false', '-e', 'MELHAT_HELMETMEDIA_ENABLED=false',
                '-e', 'MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY=' + media_key,
                '-e', 'HEADBAND_SERVER=http://127.0.0.1:1', '-e', 'TOKEN_SERVICE_USERNAME=', '-e', 'TOKEN_SERVICE_PASSWORD=',
                image, *command]
    run(*args)
    healthy(18085, metadata['backend'])
    metadata.update(ready=True, image=image, imageId=inspect(metadata['backend'])['Image'])
    write_json(folder / 'stage.json', metadata)
    return metadata


def healthy(port, container=None):
    deadline = time.monotonic() + 100
    while time.monotonic() < deadline:
        try:
            if container:
                result = json.loads(run('exec', container, 'curl', '--fail', '--silent', '--max-time', '3',
                                        'http://127.0.0.1:18084/captchaImage'))
            else:
                with urllib.request.urlopen('http://127.0.0.1:' + str(port) + '/captchaImage', timeout=3) as response:
                    result = json.load(response)
            if result.get('code') == 200:
                return
        except Exception:
            pass
        time.sleep(1)
    raise RuntimeError('Backend health check did not pass')


def database_settings(container):
    options = dict(arg.split('=', 1) for arg in container['Config'].get('Cmd', []) if '=' in arg)
    fields = ('url', 'username', 'password')
    result = {}
    for field in fields:
        key = '--spring.datasource.druid.master.' + field
        if key not in options:
            raise RuntimeError('Cannot identify existing database connection without guessing')
        result[field] = options[key]
    return result


def business_initialized(container=MYSQL):
    exists = sql(container, "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='new-helmet' AND table_name='wearable_business_meta';")
    return exists.strip() == b'1' and sql(container, "SELECT COUNT(*) FROM wearable_business_meta WHERE namespace='guardian';").strip() == b'1'


def prepare_offline_import(container, writer, manifest):
    try:
        backend = inspect(writer)
    except RuntimeError:
        backend = None
    if backend is not None and backend['State']['Running']:
        raise RuntimeError('Offline import requires the identified business writer to be stopped')
    current = sql(container, 'SELECT COALESCE(MAX(sequence),0),SUM(processed_at IS NULL) FROM wearable_device_report;').decode().strip().split('\t')
    if int(current[0]) != manifest['reportWatermark'] or current[1] not in ('0', 'NULL'):
        raise RuntimeError('Offline import requires the exact exported watermark with no pending reports')
    # Initialize only a missing singleton. Never reset an existing persisted maintenance mode.
    sql(container, "CREATE TABLE IF NOT EXISTS wearable_runtime_control (control_key VARCHAR(32) PRIMARY KEY, mode VARCHAR(16) NOT NULL, updated_at BIGINT NOT NULL, updated_by VARCHAR(128));\n"
                   "INSERT INTO wearable_runtime_control(control_key,mode,updated_at,updated_by) VALUES ('global','ACTIVE'," + str(int(time.time() * 1000)) + ",NULL) ON DUPLICATE KEY UPDATE control_key=control_key;")


def business_cli(image, container, key, directory, operation, require_drained=True):
    if operation not in ('Export', 'Import'):
        raise RuntimeError('Unsupported business operation')
    directory = directory.resolve()
    directory.parent.mkdir(parents=True, exist_ok=True)
    connection = database_settings(container)
    networks = list(container['NetworkSettings']['Networks'])
    if len(networks) != 1:
        raise RuntimeError('Business CLI requires an unambiguous database network')
    args = ['run', '--rm', '--network', networks[0], '--entrypoint', 'java',
            '-v', str(directory.parent) + ':/private-export',
            '-e', 'WEARABLE_EXPORT_JDBC_URL=' + connection['url'],
            '-e', 'WEARABLE_EXPORT_USERNAME=' + connection['username'],
            '-e', 'WEARABLE_EXPORT_PASSWORD=' + connection['password'],
            '-e', 'MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY=' + key,
            image, '-Dloader.main=com.ruoyi.guardian.WearableBusiness' + operation,
            '-cp', '/app/fdc-admin.jar', 'org.springframework.boot.loader.PropertiesLauncher',
            '/private-export/' + directory.name]
    run(*args)
    marker = directory / ('manifest.json' if operation == 'Export' else 'import-result.json')
    if not marker.is_file():
        raise RuntimeError('Business ' + operation + ' did not produce its completion marker')
    result = read_json(marker)
    if operation == 'Export' and (not result.get('guardianInitialized') or require_drained and result.get('pendingReports') != 0):
        raise RuntimeError('Export has unprocessed device reports; replay them before changing storage authority')
    return result


def copy_current_state(container, destination):
    destination.mkdir(parents=True, exist_ok=False)
    for name in STATE_FILES:
        run('cp', container + ':/data/' + name, str(destination / name))


def current_authority(container):
    try:
        payload = run('cp', container + ':/data/wearable-business-authority.json', '-')
        import io
        with tarfile.open(fileobj=io.BytesIO(payload)) as archive:
            member = next(item for item in archive.getmembers() if item.isfile())
            return json.load(archive.extractfile(member))
    except RuntimeError:
        return {'mode': 'auto'}


def write_authority(container, directory, mode, manifest=None):
    path = directory / 'wearable-business-authority.json'
    write_json(path, {'mode': mode, 'changedAt': now(), 'manifest': manifest or {}})
    run('cp', str(path), container + ':/data/wearable-business-authority.json')


def recreate_args(container, image, media_key):
    networks = list(container['NetworkSettings']['Networks'])
    if len(networks) != 1:
        raise RuntimeError('Expected a single daily backend network')
    args = ['run', '-d', '--name', LIVE, '--restart', container['HostConfig']['RestartPolicy'].get('Name') or 'unless-stopped',
            '--network', networks[0]]
    for destination, bindings in container['HostConfig'].get('PortBindings', {}).items():
        for binding in bindings or []:
            host = binding.get('HostIp', '')
            if ':' in host and not host.startswith('['):
                host = '[' + host + ']'
            args += ['-p', (host + ':' if host else '') + binding['HostPort'] + ':' + destination]
    for mount in container.get('Mounts', []):
        if mount['Type'] not in ('volume', 'bind'):
            raise RuntimeError('Unsupported daily mount type; cannot safely recreate')
        args += ['-v', (mount['Name'] if mount['Type'] == 'volume' else mount['Source']) + ':' + mount['Destination'] + ('' if mount['RW'] else ':ro')]
    env = dict(value.split('=', 1) for value in container['Config'].get('Env', []) if '=' in value)
    env.update(MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY=media_key, MELHAT_DEMO_MODE='false')
    for name, value in env.items():
        args += ['-e', name + '=' + value]
    return args + [image, *(container['Config'].get('Cmd') or [])]


def unchanged_real_history(before, after, external_links=()):
    for key in ('events', 'locations', 'media', 'calls', 'broadcasts', 'sharedCommunications'):
        expected = [row for row in before.get(key, []) if row.get('deviceId') in REAL_DEVICES]
        actual = [row for row in after.get(key, []) if row.get('deviceId') in REAL_DEVICES]
        if key == 'events':
            expected = copy.deepcopy(expected)
            for row in expected:
                if external_placeholder(row, external_links):
                    row['externalId'] = ''
                    row['externalStatus'] = '未接入外部系统'
        if expected != actual:
            raise RuntimeError('Cleanup changed real device history: ' + key)
    real_events = {row['id'] for row in before.get('events', []) if row.get('deviceId') in REAL_DEVICES}
    for event_id, value in before.get('assistance', {}).items():
        if event_id in real_events and after.get('assistance', {}).get(event_id) != value:
            raise RuntimeError('Cleanup changed real SOS assistance history')


def admin_token(path):
    if not path:
        raise RuntimeError('A private administrator token file is required')
    token = pathlib.Path(path).read_text(encoding='utf-8-sig').strip()
    if not re.fullmatch(r'[A-Za-z0-9_-]{43}', token):
        raise RuntimeError('Administrator token file does not contain one valid session token')
    return token


class AdminApiError(RuntimeError):
    def __init__(self, status):
        self.status = status
        super().__init__('Administrator API rejected operation with HTTP ' + str(status))


def admin_api(token, path, body=None, port=18084):
    request = urllib.request.Request('http://127.0.0.1:' + str(port) + '/api/admin/v1/' + path,
                                     data=None if body is None else encode(body).encode(),
                                     headers={'X-Wearable-Token': token, 'Content-Type': 'application/json'},
                                     method='GET' if body is None else 'POST')
    try:
        with urllib.request.urlopen(request, timeout=45) as response:
            payload = json.load(response)
    except urllib.error.HTTPError as error:
        raise AdminApiError(error.code) from None
    except (urllib.error.URLError, TimeoutError):
        raise RuntimeError('Administrator API is unavailable') from None
    if payload.get('code', 200) != 200:
        raise RuntimeError('Administrator API did not confirm success')
    return payload.get('data', payload)


def maintenance(token, mode=None):
    try:
        state = admin_api(token, 'maintenance', None if mode is None else {'mode': mode})
    except AdminApiError as error:
        if error.status != 503 or mode != 'PAUSED':
            raise
        state = admin_api(token, 'maintenance')
    if mode == 'PAUSED':
        deadline = time.monotonic() + 45
        while state.get('paused') and not state.get('quiescent'):
            if time.monotonic() >= deadline:
                raise RuntimeError('Maintenance remains paused but active writes have not drained')
            time.sleep(1)
            state = admin_api(token, 'maintenance')
        if not state.get('quiescent') or state.get('activeWrites') != 0:
            raise RuntimeError('Maintenance is not quiescent; cleanup must not start')
    if mode and (state.get('mode') != mode or state.get('paused') != (mode == 'PAUSED')):
        raise RuntimeError('Maintenance transition was not confirmed')
    return state


class NoLocalRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, new_url):
        raise RuntimeError('Local initialization API must not redirect')


def guardian_local_api(path, token=None, body=None, allow_missing=False):
    # Only this backend's loopback API is allowed; neither credentials nor tokens follow redirects.
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['X-Wearable-Token'] = token
    request = urllib.request.Request('http://127.0.0.1:18084/api/guardian/v1/' + path,
                                     data=None if body is None else encode(body).encode('utf-8'),
                                     headers=headers, method='GET' if body is None else 'POST')
    try:
        with urllib.request.build_opener(NoLocalRedirect()).open(request, timeout=45) as response:
            payload = json.load(response)
    except urllib.error.HTTPError as error:
        if allow_missing and body is None and error.code == 404:
            return None
        raise RuntimeError('Local initialization API rejected operation with HTTP ' + str(error.code)) from None
    except (urllib.error.URLError, TimeoutError):
        raise RuntimeError('Local initialization API is unavailable') from None
    if payload.get('code', 200) != 200:
        raise RuntimeError('Local initialization API did not confirm success')
    return payload


def local_portal_token():
    # A normal local login creates the correct guardian-audience session; admin tokens are not reused.
    document = WORKSPACE / 'output/device-ready/本地联调账号.md'
    try:
        rows = [[cell.strip().strip('`') for cell in line.strip().strip('|').split('|')]
                for line in document.read_text(encoding='utf-8-sig').splitlines() if line.strip().startswith('|')]
        header = next(row for row in rows if '用途' in row and '账号' in row and '密码' in row)
        matches = [row for row in rows if len(row) == len(header) and row[header.index('用途')].endswith('系统管理员')]
        if len(matches) != 1:
            raise ValueError('Ambiguous local account')
        account, password = matches[0][header.index('账号')], matches[0][header.index('密码')]
    except (OSError, ValueError, StopIteration):
        raise RuntimeError('Supply --portal-token-file or one documented local system administrator login') from None
    reply = guardian_local_api('login', body={'account': account, 'password': password})
    token = reply.get('token', '')
    if not isinstance(token, str) or not re.fullmatch(r'[A-Za-z0-9_-]{43}', token):
        raise RuntimeError('Local portal login did not return a valid session token')
    return token


def business_namespaces(container=MYSQL):
    return {name: int(revision) for name, revision in
            (line.split('\t') for line in sql(container, "SELECT namespace,revision FROM wearable_business_meta WHERE namespace IN ('guardian','media');").decode().splitlines())}


def initialize_business_stores(token, legacy_directory, portal_token=None):
    status = maintenance(token)
    if status.get('mode') != 'ACTIVE' or status.get('paused') is not False:
        raise RuntimeError('Business storage must initialize while the upgraded backend is ACTIVE')
    initial = business_namespaces()
    if initial.get('guardian', 0) < 1:
        admin_api(token, 'query', {'kind': 'devices', 'input': {'siteId': 'site-1', 'pageNum': 1, 'pageSize': 50}})
    if initial.get('media', 0) < 1:
        media = read_json(legacy_directory / 'helmet-media-private.json')
        calls = media.get('calls') or {}
        if not isinstance(calls, dict):
            raise RuntimeError('Stopped legacy media call journal has an unexpected shape')
        call_id = str(next(iter(calls), 'wearable-storage-initialization-missing-call'))
        session = portal_token or local_portal_token()
        # Reading a missing or differently owned call may return 404 after opening the private store.
        # No provisioning, device command, live stream, cloud request or remote login is issued here.
        response = guardian_local_api('helmet/calls/' + urllib.parse.quote(call_id, safe=''), session, allow_missing=True)
        if not calls and response is not None:
            raise RuntimeError('The fixed initialization probe must be a missing call')
    initialized = business_namespaces()
    if any(initialized.get(name, 0) < 1 for name in ('guardian', 'media')):
        raise RuntimeError('Guardian and media SQL storage must both initialize before maintenance pause or export')
    return {'initializedAt': now(), 'namespaces': initialized,
            'guardianReadRequired': initial.get('guardian', 0) < 1,
            'mediaReadRequired': initial.get('media', 0) < 1}


def wait_replayed(watermark, timeout=90):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        count = sql(MYSQL, 'SELECT COUNT(*) FROM wearable_device_report WHERE processed_at IS NULL AND sequence<=' + str(int(watermark)) + ';')
        if count.strip() == b'0':
            return
        time.sleep(1)
    raise RuntimeError('Pending reports were not replayed through the cleanup watermark')


def release(folder, token_path, portal_token_path=None):
    folder = safe_folder(folder)
    metadata = read_json(folder / 'stage.json')
    token = admin_token(token_path)
    portal_token = admin_token(portal_token_path) if portal_token_path else None
    identity = admin_api(token, 'state')
    accounts = identity.get('state', {}).get('accounts', [])
    if not any(row.get('id') == 'demo-system' for row in accounts):
        raise RuntimeError('Maintenance requires the existing system administrator session')
    if not metadata.get('ready') or not metadata.get('restoreVerified') or not metadata.get('cleanupVerified'):
        raise RuntimeError('A successfully tested isolated backend and restore are required')
    if not metadata.get('acceptanceVerified') or metadata.get('acceptanceImageId') != metadata.get('imageId'):
        raise RuntimeError('Isolated three-client, restart and pending-report acceptance must pass for this image')
    if metadata.get('cleanupToolSha256') != script_hash() \
            or metadata.get('acceptanceToolSha256') != script_hash('verify-wearable-business-stage.py'):
        raise RuntimeError('Release or acceptance script changed after rehearsal; repeat the isolated stage')
    if (folder / 'release.json').exists():
        raise RuntimeError('Release has already started; inspect its receipt instead of repeating it')
    live = inspect(LIVE)
    image = metadata.get('imageId')
    if not image or inspect(metadata['backend'])['Image'] != image:
        raise RuntimeError('Accepted isolated image identity changed')
    media_key = read_json(folder / 'baseline/business-keys.private.json')['MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY']
    cutover = folder / 'cutover'
    cutover.mkdir()
    write_json(cutover / 'previous-container.private.json', live)
    receipt = {'startedAt': now(), 'status': 'preparing', 'previousContainerId': live['Id'],
               'previousImageId': live['Image'], 'newImageId': image,
               'previousContainerName': 'melhat-before-' + folder.name.removeprefix('wearable-release-'),
               'databaseRollback': 'never overwrite current DB with baseline dump',
               'strategy': 'compatible-upgrade-then-online-maintenance-cleanup'}
    write_json(folder / 'release.json', receipt)
    # First and only normal-release interruption: install persistence and maintenance without cleanup.
    run('stop', '--time', '30', LIVE)
    try:
        (cutover / 'database.sql').write_bytes(dump())
        copy_current_state(LIVE, cutover / 'legacy-state')
        authority = current_authority(LIVE)
        initialized = business_initialized()
        if initialized and authority.get('mode') == 'legacy-file':
            manifest = business_cli(image, live, media_key, cutover / 'prior-sql', 'Export')
            manifest['importMedia'] = True
            write_json(cutover / 'legacy-state/manifest.json', manifest)
            prepare_offline_import(MYSQL, LIVE, manifest)
            business_cli(image, live, media_key, cutover / 'legacy-state', 'Import')
        run('rename', LIVE, receipt['previousContainerName'])
        receipt['status'] = 'starting-compatible-upgrade'
        write_json(folder / 'release.json', receipt)
        run(*recreate_args(live, image, media_key))
        healthy(18084)
        upgraded = inspect(LIVE)
        receipt.update(status='compatible-upgrade-ready', newContainerId=upgraded['Id'])
        write_json(folder / 'release.json', receipt)
        initialized = initialize_business_stores(token, cutover / 'legacy-state', portal_token)
        write_json(cutover / 'storage-initialized.json', initialized)
        paused = maintenance(token, 'PAUSED')
        receipt.update(status='paused-for-cleanup', pauseWatermark=paused['lastSequence'])
        write_json(folder / 'release.json', receipt)
        write_json(cutover / 'maintenance-paused.json', paused)
        # Devices remain connected and raw reports continue to be appended. No old dump is restored.
        (cutover / 'pre-cleanup-database.sql').write_bytes(dump())
        export_manifest = business_cli(image, upgraded, media_key, cutover / 'sql-current', 'Export', require_drained=False)
        original = read_json(cutover / 'sql-current/guardian-state.json')
        links = external_references()
        clean, archive_guardian = prune_guardian(original, external_links=links)
        unchanged_real_history(original, clean, links)
        clean_dir = cutover / 'clean-state'
        clean_dir.mkdir()
        write_json(clean_dir / 'guardian-state.json', clean)
        if (cutover / 'sql-current/helmet-media-private.json').exists():
            shutil.copy2(cutover / 'sql-current/helmet-media-private.json', clean_dir / 'helmet-media-private.json')
        before = ledger_snapshot(MYSQL)
        after, archive_ledger = prune_ledger(before, clean)
        write_json(cutover / 'ledger-before.private.json', before)
        write_json(cutover / 'ledger-after.private.json', after)
        write_json(cutover / 'quarantine.private.json', archive_guardian + archive_ledger)
        plan = ledger_cleanup_sql(before, after, archive_guardian + archive_ledger, folder.name)
        removed = {row.get('portalDeviceId') or row.get('code') or row['id'] for row in before['devices'] if row['id'] not in LEDGER_IDS}
        plan += '\n' + old_demo_cleanup_sql(folder.name, legacy_columns(MYSQL), removed)
        (cutover / 'cleanup.private.sql').write_text(plan, encoding='utf-8')
        sql(MYSQL, plan)
        write_json(clean_dir / 'manifest.json', export_manifest)
        business_cli(image, upgraded, media_key, clean_dir, 'Import')
        # These are current cleaned compatibility files, never the pre-stage snapshot.
        for name in STATE_FILES:
            if (clean_dir / name).is_file():
                run('cp', str(clean_dir / name), LIVE + ':/data/' + name)
        write_authority(LIVE, cutover, 'sql')
        if {row['id'] for row in rows(MYSQL, 'wearable_device')} != LEDGER_IDS:
            raise RuntimeError('Daily ledger verification did not retain exactly three devices')
        resume_watermark = maintenance(token)['lastSequence']
        resumed = maintenance(token, 'ACTIVE')
        write_json(cutover / 'maintenance-resumed.json', resumed)
        wait_replayed(resume_watermark)
        receipt.update(status='released', releasedAt=now(), replayedThrough=resume_watermark,
                       deviceIds=sorted(LEDGER_IDS), newContainerId=inspect(LIVE)['Id'])
        write_json(folder / 'release.json', receipt)
        return receipt
    except Exception:
        receipt['status'] = 'requires-recovery'
        write_json(folder / 'release.json', receipt)
        # An old mirror must never be started automatically after a newer SQL writer has run.
        # Keep exact containers and current SQL for the rollback command to export safely.
        raise


def rollback(folder, token_path):
    folder = safe_folder(folder)
    token = admin_token(token_path)
    receipt = read_json(folder / 'release.json')
    live = inspect(LIVE)
    old = inspect(receipt['previousContainerName'])
    if old['Id'] != receipt['previousContainerId'] or old['State']['Running']:
        raise RuntimeError('Expected retained stopped predecessor container')
    compatibility = folder / 'legacy-rollback-acceptance.json'
    if not compatibility.is_file():
        raise RuntimeError('Old image rollback requires isolated proof it does not recreate seed data; retain current SQL writer for recovery')
    accepted = read_json(compatibility)
    if not accepted.get('passed') or not accepted.get('emptyCollectionsPreserved') or accepted.get('imageId') != receipt['previousImageId']:
        raise RuntimeError('Old image rollback compatibility evidence does not match the retained image')
    stamp = dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ').lower()
    directory = folder / ('rollback-' + stamp)
    directory.mkdir()
    media_key = read_json(folder / 'baseline/business-keys.private.json')['MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY']
    write_json(directory / 'current-container.private.json', live)
    # Drain maintenance's backlog using the still-compatible SQL version before stopping it.
    status = maintenance(token)
    if status.get('paused'):
        maintenance(token, 'ACTIVE')
    wait_replayed(status['lastSequence'])
    run('stop', '--time', '30', LIVE)
    try:
        (directory / 'current-database.sql').write_bytes(dump())
        manifest = business_cli(receipt['newImageId'], live, media_key, directory / 'current-export', 'Export')
    except Exception:
        # A receipt can arrive between the earlier drain check and shutdown. Keep the
        # SQL-compatible writer available to recover it; never bypass export's pending check.
        run('start', LIVE)
        healthy(18084)
        recovered = maintenance(token, 'ACTIVE')
        wait_replayed(recovered['lastSequence'])
        raise RuntimeError('Old-image rollback refused; current SQL backend restarted and received reports replayed. Inspect the current-export evidence before retrying.') from None
    state = read_json(directory / 'current-export/guardian-state.json')
    if {row['id'] for row in state['devices']} != DEVICE_IDS:
        raise RuntimeError('Current SQL export is not the expected cleaned inventory')
    for name in STATE_FILES:
        source = directory / 'current-export' / name
        if source.is_file():
            run('cp', str(source), receipt['previousContainerName'] + ':/data/' + name)
    write_authority(receipt['previousContainerName'], directory, 'legacy-file', manifest)
    failed_name = 'melhat-after-' + folder.name.removeprefix('wearable-release-') + '-' + stamp
    run('rename', LIVE, failed_name)
    # Recreate the predecessor with the SAME encryption key retained in its environment.
    # A future controlled upgrade can then import changes made while files were authoritative.
    run(*recreate_args(old, receipt['previousImageId'], media_key))
    healthy(18084)
    # All additive SQL and the append-only receive journal remain untouched.
    receipt.update(status='rolled-back-current-data-preserved', rollbackAt=now(), rollbackExport=directory.name,
                   rollbackReportWatermark=manifest['reportWatermark'], retainedNewContainer=failed_name,
                   authority='legacy-file-until-next-controlled-import')
    write_json(folder / 'release.json', receipt)
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('preview', 'stage', 'release', 'rollback'))
    parser.add_argument('folder', nargs='?')
    parser.add_argument('--image')
    parser.add_argument('--admin-token-file')
    parser.add_argument('--portal-token-file', help='Existing private guardian-audience session; otherwise use the documented local administrator login only if media storage needs initialization')
    args = parser.parse_args()
    if args.mode == 'preview':
        folder, _ = new_folder()
        result = backup(folder)
        print(encode({'mode': 'preview', 'folder': str(folder), 'before': result['guardianBefore'],
                      'after': result['guardianAfter'], 'quarantined': result['quarantinedCount']}))
    elif not args.folder:
        parser.error('This mode requires a verified release folder')
    elif args.mode == 'stage':
        result = stage(args.folder, args.image)
        print(encode({k: result[k] for k in ('mysql', 'backend', 'ready', 'restoreVerified', 'cleanupVerified', 'cleanDeviceIds')}))
    elif args.mode == 'release':
        print(encode(release(args.folder, args.admin_token_file, args.portal_token_file)))
    else:
        print(encode(rollback(args.folder, args.admin_token_file)))


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    sys.stderr.reconfigure(encoding='utf-8')
    try:
        main()
    except subprocess.TimeoutExpired:
        print('Docker operation timed out; inspect the isolated release evidence before retrying', file=sys.stderr)
        sys.exit(1)
    except (RuntimeError, ValueError, OSError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
