"""Export the explicitly identified local development database without stopping writers.

Only the known melhat-mysql database and matching running backend may be read.
No source SQL is changed, no maintenance mode is entered, and no container is
started/stopped. An InnoDB single-transaction dump is the reconciliation source;
counts queried from the changing live database are never treated as dump counts.
The resulting directory contains private data and must not be shared with Fuda.
"""
import argparse
import base64
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import sys


MYSQL = 'melhat-mysql'
BACKEND = 'melhat-backend'
DATABASE = 'new-helmet'
KEY_NAME = 'MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY'
HERE = Path(__file__).resolve().parent
PRIVATE_ROOT = HERE / '.private' / 'snapshots'


def run(args, body=None, timeout=300):
    completed = subprocess.run(args, input=body, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, timeout=timeout)
    if completed.returncode:
        # Raw Docker/mysql errors or inspect data may contain private configuration.
        raise RuntimeError('Source operation failed (exit %s); no private command output was printed.' % completed.returncode)
    return completed.stdout


def inspect_source(name, expected_volume, destination):
    if name not in (MYSQL, BACKEND):
        raise ValueError('Source container is outside the fixed allowlist')
    info = json.loads(run(['docker', 'inspect', name], timeout=30))[0]
    if info.get('Name') != '/' + name or not info.get('State', {}).get('Running'):
        raise ValueError('Expected source container is not running')
    matching = [m for m in info.get('Mounts', []) if m.get('Destination') == destination]
    if len(matching) != 1 or matching[0].get('Type') != 'volume' or matching[0].get('Name') != expected_volume:
        raise ValueError('Source data volume does not match the known local deployment')
    if name == MYSQL and (info.get('Config', {}).get('Labels') or {}).get('com.docker.compose.project') != 'local-dev':
        raise ValueError('Source MySQL project does not match local-dev')
    return info


def media_key(backend):
    values = [value.split('=', 1)[1] for value in backend['Config'].get('Env', [])
              if value.startswith(KEY_NAME + '=')]
    if len(values) != 1:
        raise ValueError('A single existing media encryption key is required')
    try:
        valid = len(base64.b64decode(values[0], validate=True)) == 32
    except (ValueError, TypeError):
        valid = False
    if not valid:
        raise ValueError('Existing media encryption key is invalid; no replacement is generated')
    return values[0]


def source_tables():
    statement = ("SELECT TABLE_NAME,ENGINE FROM information_schema.tables "
                 "WHERE TABLE_SCHEMA='new-helmet' AND TABLE_TYPE='BASE TABLE' ORDER BY TABLE_NAME;")
    raw = run(['docker', 'exec', '-i', MYSQL, 'sh', '-c',
        'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot --batch --skip-column-names --default-character-set=utf8mb4 new-helmet'],
        statement.encode('utf-8'), timeout=60)
    tables = {}
    for line in raw.decode('utf-8').splitlines():
        name, engine = line.split('\t')
        if not re.fullmatch(r'[A-Za-z0-9_]+', name):
            raise ValueError('Unexpected source table name')
        if engine != 'InnoDB':
            raise ValueError('Non-InnoDB table found; online consistency requires a separate plan')
        tables[name] = engine
    if not {'wearable_device', 'wearable_business_meta', 'wearable_device_report'} <= tables.keys():
        raise ValueError('Expected current SQL wearable tables are missing')
    return tables


def dump_counts(data):
    # --skip-extended-insert makes each INSERT exactly one row. Escaped newlines
    # inside MySQL string literals do not become independent INSERT statements.
    names = re.findall(rb'^CREATE TABLE `([A-Za-z0-9_]+)`', data, re.M)
    if len(names) != len(set(names)) or not names:
        raise ValueError('Dump table definitions are absent or ambiguous')
    counts = {name.decode('ascii'): 0 for name in names}
    for name in re.findall(rb'^INSERT INTO `([A-Za-z0-9_]+)`', data, re.M):
        decoded = name.decode('ascii')
        if decoded not in counts:
            raise ValueError('Dump row has no matching table definition')
        counts[decoded] += 1
    if not {'wearable_device', 'wearable_business_meta', 'wearable_device_report'} <= counts.keys():
        raise ValueError('Dump does not contain current wearable tables')
    return counts


def schema_signature(tables):
    statement = '\n'.join('SHOW CREATE TABLE `' + name + '`;' for name in sorted(tables))
    raw = run(['docker', 'exec', '-i', MYSQL, 'sh', '-c',
        'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot --batch --skip-column-names --default-character-set=utf8mb4 new-helmet'],
        statement.encode('ascii'), timeout=60)
    # AUTO_INCREMENT's current next value changes during ordinary live inserts;
    # column, index and other table DDL must remain unchanged across the dump.
    normalized = re.sub(rb'\bAUTO_INCREMENT=\d+\b', b'AUTO_INCREMENT=<dynamic>', raw)
    return hashlib.sha256(normalized).hexdigest()


def private_write(path, data):
    with os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'wb') as stream:
        stream.write(data)


def prepare_destination(requested=None):
    root = PRIVATE_ROOT.resolve()
    name = 'source-' + dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '-' + secrets.token_hex(4)
    destination = Path(requested).resolve() if requested else root / name
    if destination.parent != root or not re.fullmatch(r'source-\d{8}T\d{6}Z-[0-9a-f]{8}', destination.name):
        raise ValueError('Output must be a new source-YYYYMMDDTHHMMSSZ-8hex directory in .private/snapshots')
    if destination.exists():
        raise ValueError('Snapshot destination already exists; existing backups are never overwritten')
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    destination.mkdir(mode=0o700, exist_ok=False)
    private_write(destination / 'INCOMPLETE', b'Export has not passed validation. Do not restore yet.\n')
    return destination


def export_snapshot(requested=None):
    mysql = inspect_source(MYSQL, 'local-dev_melhat-mysql-data', '/var/lib/mysql')
    backend = inspect_source(BACKEND, 'local-dev_melhat-backend-data', '/data')
    key = media_key(backend)
    tables = source_tables()
    schema_before = schema_signature(tables)
    destination = prepare_destination(requested)
    started = dt.datetime.now(dt.timezone.utc).isoformat()
    data = run(['docker', 'exec', MYSQL, 'sh', '-c',
        'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysqldump -uroot '
        '--single-transaction --skip-lock-tables --skip-extended-insert --complete-insert '
        '--routines --triggers --hex-blob --set-gtid-purged=OFF --no-tablespaces '
        '--default-character-set=utf8mb4 new-helmet'])
    counts = dump_counts(data)
    if counts.keys() != tables.keys() or source_tables() != tables or schema_signature(tables) != schema_before:
        raise ValueError('Source schema changed while exporting; retain evidence and repeat a fresh snapshot')
    after_mysql = inspect_source(MYSQL, 'local-dev_melhat-mysql-data', '/var/lib/mysql')
    after_backend = inspect_source(BACKEND, 'local-dev_melhat-backend-data', '/data')
    if after_mysql['Id'] != mysql['Id'] or after_backend['Id'] != backend['Id'] or media_key(after_backend) != key:
        raise ValueError('Source container or encryption configuration changed during export')
    digest = hashlib.sha256(data).hexdigest()
    private_write(destination / 'database.sql', data)
    private_write(destination / 'database.sql.sha256', (digest + '\n').encode('ascii'))
    private_write(destination / 'media-key.private.json',
                  (json.dumps({KEY_NAME: key}, indent=2) + '\n').encode('utf-8'))
    manifest = {
        'formatVersion': 1, 'purpose': 'isolated-staging-rehearsal', 'database': DATABASE,
        'startedAt': started, 'completedAt': dt.datetime.now(dt.timezone.utc).isoformat(),
        'sourceMysqlContainer': MYSQL, 'sourceMysqlId': mysql['Id'],
        'sourceBackendContainer': BACKEND, 'sourceBackendId': backend['Id'],
        'sourceBackendImage': backend['Image'], 'sourceWritersStopped': False,
        'consistency': 'InnoDB single-transaction SQL snapshot; no concurrent DDL is permitted',
        'databaseSha256': digest, 'databaseBytes': len(data),
        'tableSchemaSha256': schema_before,
        'tableCount': len(counts), 'counts': counts,
        'countSource': 'one-row-per-INSERT dump, not independently sampled live counts',
        'mediaKeyFile': 'media-key.private.json', 'mediaKeyGenerated': False,
        'containsPrivateData': True, 'filesArchiveIncluded': False,
        'notSuitableForFinalCutover': True,
    }
    private_write(destination / 'snapshot-manifest.json',
                  (json.dumps(manifest, ensure_ascii=False, indent=2) + '\n').encode('utf-8'))
    (destination / 'INCOMPLETE').unlink()
    return {'privateSnapshotDirectory': str(destination), 'databaseBytes': len(data),
            'databaseSha256': digest, 'tableCount': len(counts),
            'rowCount': sum(counts.values()), 'mediaKeyCopied': True,
            'sourceMutationPerformed': False, 'finalCutoverSnapshot': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', help='Optional new directory under this script .private/snapshots')
    args = parser.parse_args()
    result = export_snapshot(args.output_dir)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    try:
        main()
    except (ValueError, RuntimeError, OSError, subprocess.SubprocessError) as error:
        detail = str(error) if isinstance(error, (ValueError, RuntimeError)) else type(error).__name__
        print('Snapshot export failed: ' + detail + '. Any INCOMPLETE directory is not eligible for restore; source services were not changed.', file=sys.stderr)
        raise SystemExit(2)
