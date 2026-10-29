"""Build, stage and release helmet business without replacing live DB/Redis or belt settings.

Evidence, copied state and rollback metadata remain in ignored build/helmet-release-*.
The QA database is an isolated clone, and every device/vendor integration is disabled there.
"""
import datetime
import json
import pathlib
import subprocess
import sys
import time
import urllib.request
import shutil

ROOT = pathlib.Path(__file__).resolve().parents[1]
DOCKER = 'docker'
STATE_FILES = ('guardian-state.json', 'helmet-media-private.json')

def override_options(command, replacements):
    """Spring joins repeated option values; replace, never append duplicates."""
    return [arg for arg in command if arg.split('=', 1)[0] not in replacements] + [key + '=' + value for key, value in replacements.items()]

def copy_state(container, destination, required=True):
    destination.mkdir(parents=True, exist_ok=True)
    copied = []
    for filename in STATE_FILES:
        try:
            run('cp', f'{container}:/data/{filename}', str(destination / filename))
            copied.append(filename)
        except RuntimeError:
            if filename == 'guardian-state.json' and required:
                raise
    return copied

def restore_state(container, directory, files):
    for filename in files:
        if filename not in STATE_FILES:
            raise RuntimeError('Unexpected state backup filename')
        run('cp', str(directory / filename), f'{container}:/data/{filename}')

def run(*args, data=None):
    result = subprocess.run([DOCKER, *args], input=data, capture_output=True)
    if result.returncode:
        # Docker errors can quote credentials from arguments. Keep detailed output private.
        raise RuntimeError('Docker operation failed: ' + args[0])
    return result.stdout

def inspect(name):
    return json.loads(run('inspect', name))[0]

def sql(statement, data=None):
    args = ['exec'] + (['-i'] if data is not None else [])
    args += ['melhat-mysql', 'sh', '-c',
             'exec mysql -uroot -p"$MYSQL_ROOT_PASSWORD" ' + ('"$1"' if data is not None else '-e "$1"'),
             'helmet-release', statement]
    return run(*args, data=data)

def healthy(port):
    for _ in range(45):
        try:
            with urllib.request.urlopen(f'http://127.0.0.1:{port}/captchaImage', timeout=3) as response:
                if response.status == 200 and json.load(response).get('code') == 200:
                    return
        except Exception:
            pass
        time.sleep(2)
    raise RuntimeError('Backend did not become ready')

def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else ''
    if mode == 'stage':
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ').lower()
        folder = ROOT / 'build' / ('helmet-release-' + stamp)
        folder.mkdir(parents=True, exist_ok=False)
        live = inspect('melhat-backend')
        assert live['Name'] == '/melhat-backend'
        image = 'melhat-backend:helmet-business-' + stamp
        build = subprocess.run([DOCKER, 'build', '-f', 'local-dev/Dockerfile', '-t', image, '.'], cwd=ROOT,
                               stdout=(folder / 'image-build.log').open('wb'), stderr=subprocess.STDOUT)
        if build.returncode:
            raise RuntimeError('Image build failed; live service was not changed')
        (folder / 'previous-container.private.json').write_text(json.dumps(live), encoding='utf-8')
        dump = run('exec', 'melhat-mysql', 'sh', '-c', 'exec mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --single-transaction new-helmet')
        if len(dump) < 10000:
            raise RuntimeError('Database backup is unexpectedly small')
        (folder / 'baseline.sql').write_bytes(dump)
        # AdminLedgerStore persists admin_ledger/admin_* tables in MySQL, not
        # wearable-admin.json. The complete SQL dump above backs up that ledger.
        baseline = folder / 'baseline-state'
        files = copy_state('melhat-backend', baseline)
        qa_data = folder / 'qa-data'
        qa_data.mkdir()
        for filename in files:
            shutil.copy2(baseline / filename, qa_data / filename)
        database = 'helmet_qa_' + stamp.replace('t', '_').replace('z', '')
        sql('CREATE DATABASE `' + database + '` CHARACTER SET utf8mb4;')
        sql(database, dump)
        qa = 'helmet-business-qa-' + stamp
        qa_redis = qa + '-redis'
        redis = inspect('melhat-redis')
        redis_args = ['run', '-d', '--name', qa_redis, '--network', 'local-dev_default']
        for value in redis['Config'].get('Env') or []:
            redis_args += ['-e', value]
        redis_args += [redis['Image'], *(redis['Config'].get('Cmd') or [])]
        run(*redis_args)
        command = [a.replace('/new-helmet?', '/' + database + '?') for a in live['Config']['Cmd']]
        command = override_options(command, {'--spring.redis.host': qa_redis, '--spring.redis.port':'6379', '--spring.redis.database':'0',
                    '--spring.quartz.auto-startup':'false', '--melhat.direct.enabled':'false', '--melhat.belt.enabled':'false', '--melhat.helmet-media.enabled':'false'})
        assert any('/' + database + '?' in a for a in command)
        assert '--spring.redis.host=' + qa_redis in command
        args = ['run', '-d', '--name', qa, '--network', 'local-dev_default', '-p', '127.0.0.1:18085:18084', '-v', str(qa_data) + ':/data',
                '-e', 'TZ=Asia/Shanghai', '-e', 'MELHAT_DEMO_MODE=false', '-e', 'HEADBAND_SERVER=http://127.0.0.1:1',
                '-e', 'TOKEN_SERVICE_USERNAME=', '-e', 'TOKEN_SERVICE_PASSWORD=', image, *command]
        run(*args)
        metadata = {'image': image, 'previousImage': live['Config']['Image'], 'previousImageId':live['Image'], 'previousContainerId':live['Id'],
                    'qa': qa, 'qaRedis':qa_redis, 'database': database, 'stamp': stamp, 'ledgerBackup':'baseline.sql (MySQL admin_ledger and normalized admin tables)'}
        (folder / 'release.json').write_text(json.dumps(metadata), encoding='utf-8')
        healthy(18085)
        metadata['qaReady'] = True
        (folder / 'release.json').write_text(json.dumps(metadata), encoding='utf-8')
        print(json.dumps({'stage': 'ready', 'folder': str(folder), 'qaPort': 18085, 'image': image}))
    elif mode == 'release' and len(sys.argv) == 3:
        folder = pathlib.Path(sys.argv[2]).resolve()
        assert folder.parent == (ROOT / 'build').resolve() and folder.name.startswith('helmet-release-')
        metadata = json.loads((folder / 'release.json').read_text(encoding='utf-8'))
        assert metadata['qaReady']
        live = inspect('melhat-backend')
        assert live['Image'] == metadata['previousImageId'] and live['Id'] == metadata['previousContainerId'], 'Live service changed since staging'
        previous = 'melhat-backend-before-' + metadata['stamp']
        args = ['run', '-d', '--name', 'melhat-backend', '--restart', 'unless-stopped', '--network', 'local-dev_default']
        for destination, binds in live['HostConfig']['PortBindings'].items():
            for binding in binds:
                args += ['-p', (binding['HostIp'] + ':' if binding['HostIp'] else '') + binding['HostPort'] + ':' + destination]
        for mount in live['Mounts']:
            source = mount['Name'] if mount['Type'] == 'volume' else mount['Source']
            args += ['-v', source + ':' + mount['Destination'] + ('' if mount['RW'] else ':ro')]
        for value in live['Config']['Env']:
            if not value.startswith('MELHAT_HELMETMEDIA_'):
                args += ['-e', value]
        release_command = override_options(live['Config']['Cmd'], {'--melhat.helmet-media.enabled':'false'})
        args += ['-e', 'MELHAT_HELMETMEDIA_ENABLED=false', metadata['image'], *release_command]
        run('stop', 'melhat-backend')
        rollback = folder / 'pre-release-state'
        try:
            files = copy_state('melhat-backend', rollback)
            latest_dump = run('exec', 'melhat-mysql', 'sh', '-c', 'exec mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --single-transaction new-helmet')
            if len(latest_dump) < 10000:
                raise RuntimeError('Pre-release database backup is unexpectedly small')
            (folder / 'pre-release.sql').write_bytes(latest_dump)
            run('rename', 'melhat-backend', previous)
        except Exception:
            run('start', 'melhat-backend')
            raise
        try:
            run(*args)
            healthy(18084)
        except Exception:
            # Keep the failed container for logs and restore the previous container/image.
            try:
                run('stop', 'melhat-backend')
                run('rename', 'melhat-backend', 'melhat-backend-failed-' + metadata['stamp'])
            except RuntimeError:
                pass
            restore_state(previous, rollback, files)
            run('rename', previous, 'melhat-backend')
            run('start', 'melhat-backend')
            healthy(18084)
            raise
        metadata['released'] = True
        metadata['rollbackContainer'] = previous
        metadata['rollbackStateFiles'] = files
        metadata['databaseRollback'] = 'Runtime rollback preserves additive SQL changes; pre-release.sql is retained for explicit database recovery.'
        (folder / 'release.json').write_text(json.dumps(metadata), encoding='utf-8')
        print(json.dumps({'released': True, 'image': metadata['image'], 'rollbackContainer': previous, 'mediaEnabled': False}))
    else:
        raise SystemExit('Use stage or release <verified-stage-folder>')

if __name__ == '__main__':
    main()
