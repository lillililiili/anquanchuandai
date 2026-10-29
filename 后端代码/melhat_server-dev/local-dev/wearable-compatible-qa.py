"""Credential-free, disposable compatibility QA; never changes the daily writer.

Uses the existing database container only for SELECT and a consistent dump. A new
internal Docker network and private MySQL/Redis/data volumes receive the copy.
Application logins, device traffic and public requests are deliberately absent.
"""
import argparse
import hashlib
import importlib.util
import json
import pathlib
import secrets
import subprocess
import sys
import time

spec = importlib.util.spec_from_file_location('container_patch', pathlib.Path(__file__).with_name('wearable-container-patch.py'))
patch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(patch)


def clone_snapshot(mysql):
    previous = patch.MYSQL
    try:
        patch.MYSQL = mysql
        return patch.snapshot()
    finally:
        patch.MYSQL = previous


def clone_sql(mysql, sql, timeout=600):
    if not mysql.startswith('wearable-compatible-qa-'):
        raise RuntimeError('Refusing SQL writes outside the dedicated QA database')
    return patch.docker('exec', '-i', mysql, 'sh', '-c',
                        'exec mysql --default-character-set=utf8mb4 -uroot -p"$MYSQL_ROOT_PASSWORD" "$1"',
                        'wearable-compatible-qa', patch.DATABASE, data=sql, timeout=timeout)


def isolated_command(command, mysql, redis, password):
    values = {
        '--spring.datasource.druid.master.url': 'jdbc:mysql://' + mysql + ':3306/' + patch.DATABASE + '?useUnicode=true&characterEncoding=utf8&useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Shanghai',
        '--spring.datasource.druid.master.username': 'root',
        '--spring.datasource.druid.master.password': password,
        '--spring.redis.host': redis, '--spring.redis.port': '6379',
        '--spring.redis.database': '0', '--spring.redis.password': '',
        '--spring.quartz.auto-startup': 'false', '--melhat.demo-mode': 'false',
        '--melhat.direct.enabled': 'false', '--melhat.belt.enabled': 'false',
        '--melhat.helmet-media.enabled': 'false',
    }
    return [value for value in command if value.split('=', 1)[0] not in values] + [key + '=' + value for key, value in values.items()]


def smoke(image, jar, directory):
    directory = pathlib.Path(directory).resolve()
    if directory.parent != patch.BUILD or directory.exists():
        raise RuntimeError('Use a new directory directly inside the workspace build directory')
    ignored = subprocess.run(['git', 'check-ignore', '-q', str(directory / 'qa-private/database.sql')],
                             cwd=patch.ROOT, capture_output=True)
    if ignored.returncode:
        raise RuntimeError('QA database copy must be ignored by Git')
    jar_hash = hashlib.sha256(pathlib.Path(jar).read_bytes()).hexdigest()
    target = patch.inspect(image)
    daily = patch.inspect(patch.LIVE)
    if not daily['State']['Running'] or target['Config']['Entrypoint'] != daily['Config']['Entrypoint']:
        raise RuntimeError('Daily service or compatible image entrypoint precondition failed')
    patch.require_standard_deployment(daily)
    directory.mkdir()
    private = directory / 'qa-private'
    private.mkdir(mode=0o700)
    patch.write_json(private / 'deployment.private.json', daily)
    initial = patch.snapshot()
    if initial['mode'] != 'ACTIVE' or initial['namespaces'] != 'guardian,media':
        raise RuntimeError('Initialized ACTIVE business storage is required')
    run = 'wearable-compatible-qa-' + secrets.token_hex(5)
    mysql, redis, backend = run + '-mysql', run + '-redis', run + '-backend'
    password = secrets.token_urlsafe(32)
    resources = {'network': run, 'mysql': mysql, 'redis': redis, 'backend': backend,
                 'mysqlVolume': run + '-mysql-data', 'backendVolume': run + '-backend-data',
                 'createdAt': patch.now()}
    patch.write_json(directory / 'qa-resources.json', resources)
    patch.write_json(private / 'clone-credentials.private.json', {'password': password})
    evidence = {'image': image, 'imageId': target['Id'], 'jarSha256': jar_hash,
                'isolatedNetwork': run, 'administratorCredentialsRead': False,
                'loginAttempted': False, 'realDeviceIntegrationsEnabled': False,
                'hostPortsExposed': False, 'databaseCommandsScope': 'live SELECT/dump; disposable QA import only',
                'dailyContainerUnchanged': False, 'passed': False}
    try:
        with (private / 'database.sql').open('wb') as output:
            patch.docker('exec', patch.MYSQL, 'sh', '-c',
                         'exec mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --single-transaction --skip-lock-tables --hex-blob --default-character-set=utf8mb4 "$1"',
                         'wearable-compatible-qa', patch.DATABASE, output=output, timeout=600)
        patch.docker('network', 'create', '--internal', '--label', 'wearable.compatible-qa=' + directory.name, run)
        patch.docker('run', '-d', '--name', mysql, '--network', run, '--label', 'wearable.compatible-qa=' + directory.name,
                     '-v', resources['mysqlVolume'] + ':/var/lib/mysql', '-e', 'MYSQL_ROOT_PASSWORD=' + password,
                     '-e', 'MYSQL_DATABASE=' + patch.DATABASE, 'mysql:8.0', '--character-set-server=utf8mb4',
                     '--collation-server=utf8mb4_unicode_ci', '--default-authentication-plugin=mysql_native_password')
        deadline = time.monotonic() + 120
        while True:
            try:
                clone_sql(mysql, b'SELECT 1;', 10)
                break
            except RuntimeError:
                if time.monotonic() >= deadline:
                    raise RuntimeError('Disposable QA database did not become ready')
                time.sleep(1)
        clone_sql(mysql, (private / 'database.sql').read_bytes())
        restored = clone_snapshot(mysql)
        patch.verify_preservation(initial, restored)
        patch.docker('run', '-d', '--name', redis, '--network', run,
                     '--label', 'wearable.compatible-qa=' + directory.name, 'redis:7-alpine')
        original_environment = dict(value.split('=', 1) for value in daily['Config'].get('Env', []) if '=' in value)
        media_key = original_environment.get('MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY')
        if not media_key:
            raise RuntimeError('Opaque media encryption configuration is absent')
        command = isolated_command(daily['Config'].get('Cmd') or [], mysql, redis, password)
        patch.docker('run', '-d', '--name', backend, '--network', run, '--label', 'wearable.compatible-qa=' + directory.name,
                     '-v', resources['backendVolume'] + ':/data', '-e', 'TZ=Asia/Shanghai',
                     '-e', 'MELHAT_DEMO_MODE=false', '-e', 'MELHAT_DIRECT_ENABLED=false',
                     '-e', 'MELHAT_BELT_ENABLED=false', '-e', 'MELHAT_HELMETMEDIA_ENABLED=false',
                     '-e', 'HEADBAND_SERVER=http://127.0.0.1:1', '-e', 'TOKEN_SERVICE_USERNAME=', '-e', 'TOKEN_SERVICE_PASSWORD=',
                     '-e', 'MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY=' + media_key, target['Id'], *command)
        current = patch.inspect(backend)
        network = json.loads(patch.docker('network', 'inspect', run))[0]
        if not network['Internal'] or set(current['NetworkSettings']['Networks']) != {run} or current['HostConfig']['PortBindings']:
            raise RuntimeError('QA isolation invariants failed')
        daily_name = patch.LIVE
        try:
            patch.LIVE = backend
            anonymous = patch.anonymous_health()
        finally:
            patch.LIVE = daily_name
        installed = patch.docker('exec', backend, 'sha256sum', '/app/fdc-admin.jar').decode().split()[0]
        if installed.lower() != jar_hash:
            raise RuntimeError('Isolated image JAR hash differs from the tested package')
        deadline = time.monotonic() + 60
        while True:
            after = clone_snapshot(mysql)
            if after['pendingReports'] == 0:
                break
            if time.monotonic() >= deadline:
                raise RuntimeError('Restored QA pending reports did not drain')
            time.sleep(1)
        patch.verify_preservation(restored, after)
        untouched = patch.inspect(daily_name)
        if untouched['Id'] != daily['Id'] or untouched['Image'] != daily['Image'] or not untouched['State']['Running']:
            raise RuntimeError('Daily container changed while QA was running')
        evidence.update(passed=True, verifiedAt=patch.now(), dailyContainerUnchanged=True,
                        healthCode=200, anonymousProtectedRequests=anonymous,
                        qaContainerId=current['Id'], before=restored, after=after)
        patch.write_json(directory / 'qa-anonymous-smoke.json', evidence)
        return evidence
    except Exception as error:
        evidence['failureType'] = type(error).__name__
        patch.write_json(directory / 'qa-anonymous-smoke.json', evidence)
        raise RuntimeError('Isolated QA failed; daily service was not modified. Inspect private evidence.') from None


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--image', required=True)
    parser.add_argument('--jar', required=True)
    parser.add_argument('--directory', required=True)
    args = parser.parse_args()
    try:
        result = smoke(args.image, args.jar, args.directory)
        print(json.dumps({'passed': result['passed'], 'imageId': result['imageId'], 'jarSha256': result['jarSha256'],
                          'evidence': str(pathlib.Path(args.directory).resolve() / 'qa-anonymous-smoke.json')}, ensure_ascii=False))
    except (RuntimeError, OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
