#!/usr/bin/env python3
"""Run offline transfer with the exact schema/JDBC dependencies from a tested application jar."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
import uuid
from urllib.parse import urlsplit
import zipfile

ROOT = Path(__file__).resolve().parent


def file_sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def docker_identity(container):
    result = subprocess.run(['docker', 'inspect', container], check=True, capture_output=True, text=True, encoding='utf-8', timeout=20)
    data = json.loads(result.stdout)
    if len(data) != 1:
        raise ValueError('One explicit container is required per inventory item.')
    return data[0]


def endpoint_matches(url, product, schema, database, app=None):
    value = urlsplit(url.removeprefix('jdbc:'))
    port = value.port or (5236 if product == 'dm8' else 3306)
    if value.scheme != ('dm' if product == 'dm8' else 'mysql') or product == 'mysql' and value.path.lstrip('/') != schema:
        return False
    internal = 5236 if product == 'dm8' else 3306
    if app is None and value.hostname in ('127.0.0.1', 'localhost'):
        return any(binding['HostPort'] == str(port) and binding['HostIp'] in ('127.0.0.1', '0.0.0.0')
                   for binding in database['NetworkSettings']['Ports'].get(f'{internal}/tcp', []) or [])
    if port != internal:
        return False
    for network, attachment in database['NetworkSettings']['Networks'].items():
        if app is not None:
            peer = app['NetworkSettings']['Networks'].get(network)
            created = app['State'].get('Status') == 'created' and app.get('HostConfig', {}).get('NetworkMode') in (network, attachment['NetworkID'])
            # A newly created, never-started target has no endpoint ID yet. Its explicit network mode is still inspectable.
            if not peer or peer.get('NetworkID') != attachment['NetworkID'] and not (created and not peer.get('NetworkID')):
                continue
        aliases = {database['Name'].lstrip('/'), attachment.get('IPAddress'),
                   *(attachment.get('Aliases') or []), *(attachment.get('DNSNames') or [])}
        if value.hostname in aliases:
            return True
    return False


def stopped_evidence(config, containers, destination):
    if not containers:
        raise ValueError('Explicit stopped application container inventory is required.')
    database = docker_identity(config['databaseContainerId'])
    if database['Id'] != config['databaseContainerId'] or not database['State']['Running']:
        raise ValueError('Database instance identity changed or is unavailable.')
    if not endpoint_matches(config['url'], config['product'], config['schema'], database):
        raise ValueError('Transfer endpoint is not the designated database instance/schema.')
    if config['product'] == 'dm8' and config['username'].upper() != config['schema'].upper():
        raise ValueError('DM schema/user mismatch.')
    private_env = dict(line.split('=', 1) for line in Path(config['backendEnvFile']).read_text(encoding='utf-8').splitlines() if '=' in line)
    if private_env.get('MELHAT_DB_USERNAME') != config['username'] or private_env.get('MELHAT_DB_PASSWORD') != config['password'] \
            or private_env.get('MELHAT_DB_PRODUCT') != config['product'] \
            or not endpoint_matches(private_env.get('MELHAT_DB_URL', ''), config['product'], config['schema'], database):
        raise ValueError('Backend configuration differs from the transfer endpoint.')
    nodes, identities = [], []
    for container in containers:
        # Configuration is inspected in memory only; it is never written to logs or evidence.
        item = docker_identity(container)
        if item['State']['Running'] or item['State'].get('Restarting') or item['State'].get('Paused'):
            raise ValueError('An application container is still active.')
        env = dict(value.split('=', 1) for value in item['Config'].get('Env', []) if '=' in value)
        if env.get('MELHAT_DB_USERNAME') != config['username'] or env.get('MELHAT_DB_PRODUCT') != config['product'] \
                or not endpoint_matches(env.get('MELHAT_DB_URL', ''), config['product'], config['schema'], database, item):
            raise ValueError('Stopped container does not match the configured database user and product.')
        for key in ('JWT_SECRET', 'MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY'):
            if not private_env.get(key) or private_env[key] != env.get(key):
                raise ValueError('Stopped application continuity keys differ from the archived configuration.')
        node = env.get('MELHAT_CLUSTER_NODE_ID')
        if node:
            nodes.append(node)
        identities.append(item['Id'])
    evidence = dict(verifiedStopped=True, schema=config['schema'], databaseContainerId=database['Id'], nodeIds=nodes, containerIds=identities,
                    capturedAt=datetime.now(timezone.utc).isoformat(), expiresAt=int((time.time() + 300) * 1000))
    destination.write_text(json.dumps(evidence), encoding='utf-8')


def extract_runtime(jar, directory):
    classes, libraries = directory / 'classes', directory / 'lib'
    classes.mkdir(); libraries.mkdir()
    with zipfile.ZipFile(jar) as archive:
        for item in archive.infolist():
            name = item.filename
            if name.startswith('BOOT-INF/lib/') and name.endswith('.jar'):
                relative = name[len('BOOT-INF/lib/'):]
                if '/' in relative or '\\' in relative:
                    raise ValueError('Invalid nested dependency path.')
                destination = libraries / relative
            elif name.startswith('BOOT-INF/classes/') and not name.endswith('/'):
                relative = name[len('BOOT-INF/classes/'):]
                if not (relative.startswith(('db/', 'com/ruoyi/database/SchemaLifecycle', 'com/ruoyi/common/database/'))):
                    continue
                if '\\' in relative or any(part in ('', '.', '..') for part in relative.split('/')):
                    raise ValueError('Invalid application class path.')
                destination = classes / relative
            else:
                continue
            if item.file_size > 256 * 1024 * 1024:
                raise ValueError('Unexpected dependency size.')
            destination.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(item) as source, destination.open('xb') as output:
                shutil.copyfileobj(source, output)
    if not (classes / 'com/ruoyi/database/SchemaLifecycle.class').is_file():
        raise ValueError('Application jar lacks the reviewed schema lifecycle.')
    return str(classes) + os.pathsep + str(libraries / '*')


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['export', 'import', 'reconcile', 'resume'])
    parser.add_argument('--application-jar', required=True, type=Path)
    parser.add_argument('--config', required=True, type=Path, help='Private endpoint configuration; never put credentials in arguments')
    parser.add_argument('--bundle', required=True, type=Path)
    parser.add_argument('--offline-app', action='append', required=True, help='Existing stopped application container; repeat for every node')
    parser.add_argument('--confirm-target')
    parser.add_argument('--journal', type=Path)
    parser.add_argument('--report', type=Path, help='New private reconciliation report; defaults to a unique file beside the bundle')
    parser.add_argument('--java', default='java')
    parser.add_argument('--work-dir', required=True, type=Path, help='Existing private temporary directory')
    args = parser.parse_args()
    work = args.work_dir.resolve(strict=True)
    if not work.is_dir() or work == Path(work.anchor) or args.work_dir.is_symlink():
        raise ValueError('Use an existing private working directory.')
    if os.name != 'nt' and (work.stat().st_mode & 0o077 or work.stat().st_uid != os.getuid()):
        raise ValueError('Working directory must be owned by this account with mode 0700.')
    if args.command in ('import', 'resume') and (not args.confirm_target or not args.journal):
        raise ValueError('Import/resume requires explicit target ID and private journal.')
    config = json.loads(args.config.read_text(encoding='utf-8'))
    if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', config['schema']):
        raise ValueError('Invalid schema identity.')
    if args.bundle.is_symlink():
        raise ValueError('Bundle must not be a symlink.')
    bundle = args.bundle.resolve()
    for private in (args.config.absolute(), Path(config['backendEnvFile']).absolute()):
        if private.is_symlink() or not private.is_file():
            raise ValueError('Private configuration must be a regular file.')
    private_directories = [work, bundle if bundle.exists() else bundle.parent]
    if args.journal:
        private_directories.append(args.journal.resolve().parent)
    report = args.report.resolve() if args.report else bundle.parent / ('reconciliation-' + str(uuid.uuid4()) + '.json')
    if args.command == 'reconcile':
        private_directories.append(report.parent)
        if report.exists() or report.is_symlink():
            raise ValueError('Reconciliation requires a new report path.')
    for directory in private_directories:
        if directory.is_symlink() or directory.resolve(strict=True) != directory or not directory.is_dir():
            raise ValueError('Use existing canonical private directories.')
        if os.name != 'nt' and (directory.stat().st_mode & 0o077 or directory.stat().st_uid != os.getuid()):
            raise ValueError('Bundle, journal and working paths require owned mode 0700 directories.')
    if args.command == 'export' and bundle.exists():
        raise ValueError('Export requires a new bundle directory.')
    with tempfile.TemporaryDirectory(prefix='transfer-', dir=work) as temporary:
        runtime = Path(temporary)
        evidence = runtime / 'offline.json'
        stopped_evidence(config, args.offline_app, evidence)
        classpath = extract_runtime(args.application_jar, runtime)
        environment = dict(os.environ, MIGRATION_DB_CONFIG=str(args.config.resolve()), MIGRATION_WORK_DIR=str(runtime),
                           MIGRATION_OFFLINE_EVIDENCE=str(evidence), MIGRATION_APPLICATION_SHA256=file_sha256(args.application_jar))
        if args.confirm_target:
            environment['MIGRATION_CONFIRM_TARGET'] = args.confirm_target
        if args.journal:
            environment['MIGRATION_JOURNAL'] = str(args.journal.resolve())
        if args.command == 'reconcile':
            environment['MIGRATION_REPORT'] = str(report)
        # Keep secret-bearing Spring/JDBC diagnostics off the console. The source tool emits only controlled status codes.
        command = [args.java, '-Dfile.encoding=UTF-8', '-Duser.timezone=UTC', '-Xmx512m', '-cp', classpath,
                   str(ROOT / 'MigrationTool.java'), args.command, str(bundle)]
        with (runtime / 'raw-output.log').open('wb') as output:
            process = subprocess.run(command, env=environment, stdout=output, stderr=subprocess.STDOUT, timeout=7200)
        lines = (runtime / 'raw-output.log').read_text(encoding='utf-8', errors='replace').splitlines()
        statuses = [line for line in lines if re.fullmatch(r'(?:PASS: (?:export|import|reconcile|resume) completed with content, identity and file checks\.|FAIL: [A-Z_]+\. Preserve the private journal and inspect the target before retrying\.)', line)]
        for line in statuses:
            print(line)
        for line in lines:
            if re.fullmatch(r'CONTEXT: [A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)?', line):
                print(line)
        if process.returncode or not statuses:
            print('Transfer failed. No credentials or raw database output were printed.', file=sys.stderr)
            return 2
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception:
        print('Transfer prerequisites failed; verify private configuration, stopped nodes, tested jar and private paths. No credentials printed.', file=sys.stderr)
        sys.exit(2)
