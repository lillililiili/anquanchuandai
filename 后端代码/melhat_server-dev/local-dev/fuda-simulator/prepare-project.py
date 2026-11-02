"""Prepare a new loopback-only project integration lab; never use an existing DB."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import secrets
import subprocess

ROOT = Path(__file__).resolve().parent
BACKEND = ROOT.parent.parent
LOCAL = ROOT / '.local' / 'integration'
DB = 'fuda-sim-it-mysql'
REDIS = 'fuda-sim-it-redis'


def run(*args, input=None):
    return subprocess.run(args, input=input, capture_output=True, check=True).stdout


def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=True, indent=2), encoding='utf-8')


def prepare():
    LOCAL.mkdir(parents=True, exist_ok=True)
    target = LOCAL / 'java-config.json'
    if target.exists():
        raise RuntimeError('Lab already prepared. Reuse it; do not reinitialize its database.')
    for name in (DB, REDIS):
        if subprocess.run(['docker', 'inspect', name], capture_output=True).returncode == 0:
            raise RuntimeError('Existing container: ' + name)
    cfg = {'javaOrigin': 'http://127.0.0.1:18095', 'javaSecret': secrets.token_hex(32),
           'deviceId': 'FUDA-IT-HELMET-01', 'ledgerId': 'device-1001',
           'dbPassword': secrets.token_hex(32), 'adminUsername': 'admin',
           'adminPassword': 'Admin@2026', 'mediaEncryptionKey': base64.b64encode(secrets.token_bytes(32)).decode(),
           'jarSha256': hashlib.sha256((BACKEND / 'ruoyi-admin/target/fdc-admin.jar').read_bytes()).hexdigest()}
    save(target, cfg)
    (LOCAL / 'mysql.env').write_text('MYSQL_ROOT_PASSWORD=' + cfg['dbPassword'] + '\nMYSQL_DATABASE=fuda_sim_it\n', encoding='utf-8')
    init = LOCAL / 'init'
    init.mkdir()
    for source, dest in [('sql/ry_20230223.sql', '01-base.sql'), ('sql/quartz.sql', '02-quartz.sql')]:
        (init / dest).write_bytes((BACKEND / source).read_bytes())
    schema = (BACKEND / 'sql/melhat_demo.sql').read_text(encoding='utf-8-sig').split('-- 先删除子记录')[0]
    (init / '03-business-schema.sql').write_text(schema, encoding='utf-8')
    (init / '04-page-schema.sql').write_bytes((BACKEND / 'sql/migrations/20260916_page_schema.sql').read_bytes())
    seed = json.loads((BACKEND / 'ruoyi-admin/src/main/resources/admin-seed.json').read_text(encoding='utf-8-sig'))
    for key in list(seed):
        if key not in ('sites', 'roles', 'accounts', 'organizations', 'areas'):
            if isinstance(seed[key], list): seed[key] = []
            elif isinstance(seed[key], dict): seed[key] = {}
    seed['revision'] = 0
    seed['nextId'] = 1000
    seed['accounts'] = [x for x in seed['accounts'] if x['id'] == 'demo-system']
    body = json.dumps(seed, ensure_ascii=True).encode().hex()
    sql = "CREATE TABLE admin_ledger (id TINYINT PRIMARY KEY,body LONGTEXT NOT NULL,updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);\n"
    sql += "INSERT INTO admin_ledger(id,body) VALUES (1,CONVERT(0x" + body + " USING utf8mb4));\nUPDATE sys_job SET status='1';\n"
    (init / '05-lab-ledger.sql').write_text(sql, encoding='utf-8')
    run('docker', 'run', '-d', '--name', DB, '--label', 'purpose=fuda-local-integration', '--memory', '512m',
        '-p', '127.0.0.1:13316:3306', '--env-file', str(LOCAL / 'mysql.env'),
        '--mount', 'type=bind,source=' + str(init) + ',target=/docker-entrypoint-initdb.d,readonly',
        'mysql:8.0', '--character-set-server=utf8mb4', '--collation-server=utf8mb4_unicode_ci', '--innodb-buffer-pool-size=128M')
    run('docker', 'run', '-d', '--name', REDIS, '--label', 'purpose=fuda-local-integration', '--memory', '96m',
        '-p', '127.0.0.1:16389:6379', 'redis:7-alpine', 'redis-server', '--appendonly', 'yes')
    print('Prepared isolated MySQL/Redis and synthetic ledger; no existing database was read or changed.')


def configure():
    cfg = json.loads((LOCAL / 'java-config.json').read_text(encoding='utf-8'))
    sim = json.loads((ROOT / '.local/config.json').read_text(encoding='utf-8'))
    media = json.loads((LOCAL / 'media-config.json').read_text(encoding='utf-8'))
    profile = {'verified': True, 'coordinate-system': 'WGS84', 'evidence': 'Synthetic loopback fixture, not device coordinate certification'}
    settings = {
      'server': {'address': '127.0.0.1', 'port': 18095},
      'spring': {'datasource': {'druid': {'master': {'url': 'jdbc:mysql://127.0.0.1:13316/fuda_sim_it?useUnicode=true&characterEncoding=utf8&useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC&nullCatalogMeansCurrent=true', 'username': 'root', 'password': cfg['dbPassword']}, 'initial-size': 2, 'min-idle': 2, 'max-active': 8}},
                 'redis': {'host': '127.0.0.1', 'port': 16389, 'database': 0, 'password': ''}, 'quartz': {'auto-startup': False}},
      'ruoyi': {'profile': str(LOCAL / 'uploads'), 'hatfile': str(LOCAL / 'hatfile'), 'task-package-file': str(LOCAL / 'tasks')},
      'melhat': {'demo-mode': False, 'business': {'media-encryption-key': cfg['mediaEncryptionKey']},
                 'direct': {'enabled': True, 'public-base-url': cfg['javaOrigin'], 'heartbeat-timeout-seconds': 45},
                 'belt': {'enabled': True, 'public-base-url': cfg['javaOrigin']},
                 'helmet-media': {'enabled': True, 'control-url': media['mediaOrigin'] + '/helmet-media/control/v1', 'shared-key': media['sharedKey']}},
      'headband': {'server': 'https://disabled.invalid', 'token': {'username': '', 'password': ''}},
      'fuda': {'gb': {'internal-enabled': True, 'internal-secret': cfg['javaSecret'], 'allowed-devices': cfg['deviceId']},
               'api': {'enabled': True, 'source-platform': 'fuda-local-integration', 'applications': {sim['appId']: {'enabled': True, 'secret-base64': sim['secretBase64'], 'allowed-ledger-device-ids': [cfg['ledgerId'], 'device-1002']}}, 'location-profiles': {cfg['ledgerId']: profile, 'device-1002': profile}},
               'push': {'enabled': True, 'destination-id': 'fuda-local-integration', 'app-id': sim['appId'], 'secret-base64': sim['secretBase64'],
                        'endpoint': 'http://127.0.0.1:19092/receive', 'allow-loopback-http': True, 'allowed-ledger-device-ids': [cfg['ledgerId'], 'device-1002'], 'retry-max-millis': 5000}},
      'logging': {'level': {'com.ruoyi': 'info', 'org.springframework': 'info'}}}
    save(LOCAL / 'application.yml', settings)
    print('Prepared local-only application override. Production files untouched; secrets not displayed.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['prepare', 'configure'])
    args = parser.parse_args()
    (prepare if args.action == 'prepare' else configure)()
