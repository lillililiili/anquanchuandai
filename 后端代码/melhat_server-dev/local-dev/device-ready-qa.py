"""Local isolated QA only. Start copies the daily DB; stop removes only the verified QA instance.

No device vendor requests are enabled. SQL backups and sessions stay in ignored build/.
"""
"""Disposable local QA only; never exposes a device provider or writes the live DB."""
import datetime, json, pathlib, subprocess, sys

docker = r'C:\Users\19221\AppData\Local\Programs\DockerDesktop\resources\bin\docker.exe'
folder = pathlib.Path(__file__).resolve().parents[1] / 'build' / ('device-ready-qa-' + datetime.datetime.now().strftime('%Y%m%d-%H%M%S'))
database = 'wearable_device_ready_qa_20261007'
name = 'wearable-device-ready-qa'

def run(*args, **kwargs):
    return subprocess.run([docker, *args], capture_output=True, check=True, **kwargs)

def sql(statement, data=None):
    args = ['exec'] + (['-i'] if data is not None else [])
    args += ['melhat-mysql', 'sh', '-c',
             'exec mysql -uroot -p"$MYSQL_ROOT_PASSWORD" ' + ('"$1"' if data is not None else '-e "$1"'),
             'isolated-qa', statement]
    return run(*args, input=data)

assert name == 'wearable-device-ready-qa' and database == 'wearable_device_ready_qa_20261007'
if sys.argv[1:] == ['stop']:
    c = json.loads(run('inspect', name).stdout)[0]
    assert c['Name'] == '/' + name
    assert any('/' + database + '?' in a for a in c['Config']['Cmd'])
    assert c['HostConfig']['PortBindings']['18084/tcp'][0]['HostPort'] == '18085'
    run('rm', '-f', name)
    sql('DROP DATABASE `' + database + '`;')
    print('Only the isolated QA container and database were removed; evidence retained.')
elif sys.argv[1:] == ['start']:
    folder.mkdir(parents=True, exist_ok=False)
    assert not (folder / 'guardian-state.json').exists(), 'QA folder already initialized'
    config = json.loads(run('inspect', 'melhat-backend').stdout)[0]['Config']
    dump = run('exec', 'melhat-mysql', 'sh', '-c',
               'exec mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --single-transaction new-helmet').stdout
    assert len(dump) > 10000
    (folder / 'baseline.sql').write_bytes(dump)
    run('cp', 'melhat-backend:/data/guardian-state.json', str(folder / 'baseline-state.json'))
    (folder / 'guardian-state.json').write_bytes((folder / 'baseline-state.json').read_bytes())
    commands = [a.replace('/new-helmet?', '/' + database + '?').replace('--spring.redis.database=10', '--spring.redis.database=12') for a in config['Cmd']]
    assert any('/' + database + '?' in a for a in commands)
    assert '--spring.redis.database=12' in commands
    commands.append('--spring.quartz.auto-startup=false')
    sql('CREATE DATABASE `' + database + '` CHARACTER SET utf8mb4;')
    sql(database, dump)
    run('run', '-d', '--name', name, '--network', 'local-dev_default',
        '-p', '127.0.0.1:18085:18084', '-v', str(folder) + ':/data',
        '-e', 'TZ=Asia/Shanghai', '-e', 'MELHAT_DEMO_MODE=true',
        '-e', 'HEADBAND_SERVER=http://127.0.0.1:1', '-e', 'TOKEN_SERVICE_USERNAME=',
        '-e', 'TOKEN_SERVICE_PASSWORD=', 'melhat-backend:dev', *commands)
    print('Isolated QA started at 127.0.0.1:18085, separate database/Redis/files, device provider disabled.')
else:
    raise SystemExit('Use start or stop')
