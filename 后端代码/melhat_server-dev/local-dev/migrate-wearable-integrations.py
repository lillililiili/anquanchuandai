"""Register deployed adapter configuration; never call an adapter or invent sync receipts."""
import importlib.util
import json
import pathlib
import sys
import urllib.parse

spec = importlib.util.spec_from_file_location('release', pathlib.Path(__file__).with_name('wearable-business-release.py'))
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)


def clean_endpoint(value):
    parsed = urllib.parse.urlsplit(value)
    if parsed.scheme not in ('http', 'https') or not parsed.hostname:
        raise RuntimeError('Deployed adapter endpoint is invalid')
    if parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise RuntimeError('Adapter endpoint must not include credentials, query or fragment')
    return urllib.parse.urlunsplit((parsed.scheme, parsed.netloc, parsed.path.rstrip('/'), '', ''))


def migrate(folder):
    folder = r.safe_folder(folder)
    live = r.inspect(r.LIVE)
    if not live['State']['Running']:
        raise RuntimeError('Expected running daily backend')
    env = dict(value.split('=', 1) for value in live['Config']['Env'] if '=' in value)
    args = dict(value.split('=', 1) for value in live['Config'].get('Cmd', []) if '=' in value)
    endpoint = args.get('--melhat.helmet-media.control-url', env.get('MELHAT_HELMETMEDIA_CONTROLURL', ''))
    enabled = args.get('--melhat.helmet-media.enabled', env.get('MELHAT_HELMETMEDIA_ENABLED', 'false')).lower() == 'true'
    if not endpoint or not env.get('MELHAT_HELMETMEDIA_SHAREDKEY'):
        raise RuntimeError('No complete deployed media configuration to register')
    desired = {'id': 'adapter-helmet-media-site-1', 'siteId': 'site-1', 'kind': 'MEDIA', 'name': '安全帽媒体服务',
               'endpoint': clean_endpoint(endpoint), 'credentialRef': 'env:MELHAT_HELMETMEDIA_SHAREDKEY',
               'managed': True, 'enabled': enabled, 'configurationSource': 'docker:melhat-backend'}
    history = folder / 'external-config-migration'
    history.mkdir(exist_ok=True)
    before = r.sql(r.MYSQL, 'SELECT HEX(body) FROM external_integration ORDER BY id;')
    backup = history / 'before.private.json'
    if not backup.exists():
        r.write_json(backup, [json.loads(bytes.fromhex(line).decode()) for line in before.decode().splitlines()])
    changed = False
    for attempt in range(3):
        rows = r.sql(r.MYSQL, 'SELECT HEX(body) FROM external_integration WHERE id=' + r.quote(desired['id']) + ';').decode().splitlines()
        if not rows:
            row = dict(desired, status='NOT_CONNECTED', lastSyncAt=None,
                       lastError='媒体适配已按部署配置登记，尚无本地外部数据同步记录',
                       version=1, updatedAt=r.now(), updatedBy='deployment-config-migration')
            statement = 'INSERT IGNORE INTO external_integration(id,site_id,kind,version,body) VALUES(' + ','.join(
                [r.quote(row['id']), r.quote(row['siteId']), r.quote(row['kind']), '1', r.quote(r.encode(row))]) + '); SELECT ROW_COUNT();'
        else:
            old = json.loads(bytes.fromhex(rows[0]).decode())
            if all(old.get(key) == value for key, value in desired.items()):
                break
            row = dict(old, **desired)
            row.update(version=int(old['version']) + 1, updatedAt=r.now(), updatedBy='deployment-config-migration')
            # Preserve any actual CONNECTED status, sync time and data produced concurrently by the adapter.
            statement = 'UPDATE external_integration SET version=' + str(row['version']) + ',body=' + r.quote(r.encode(row)) + \
                        ' WHERE id=' + r.quote(row['id']) + ' AND body=' + r.quote(r.encode(old)) + '; SELECT ROW_COUNT();'
        if r.sql(r.MYSQL, statement).strip() == b'1':
            changed = True
            break
    else:
        raise RuntimeError('Adapter configuration changed concurrently; no stale overwrite was performed')
    current = json.loads(bytes.fromhex(r.sql(r.MYSQL, 'SELECT HEX(body) FROM external_integration WHERE id=' + r.quote(desired['id']) + ';').decode().strip()).decode())
    vendor_complete = bool(env.get('HEADBAND_SERVER') and env.get('TOKEN_SERVICE_USERNAME') and env.get('TOKEN_SERVICE_PASSWORD'))
    evidence = {'verifiedAt': r.now(), 'changed': changed, 'integration': current,
                'externalRecordCount': r.table_counts(r.MYSQL, ['external_data_record'])['external_data_record'],
                'vendorEndpointPresent': bool(env.get('HEADBAND_SERVER')), 'vendorCredentialsConfigured': vendor_complete,
                'vendorRegistration': 'skipped: no configured vendor account' if not vendor_complete else 'requires explicit configured-adapter mapping',
                'networkRequestsMade': False, 'secretsStored': False}
    r.write_json(history / 'result.json', evidence)
    print(r.encode(evidence))


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    try:
        if len(sys.argv) != 2:
            raise RuntimeError('Usage: migrate-wearable-integrations.py <release-folder>')
        migrate(sys.argv[1])
    except (RuntimeError, ValueError, OSError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
