"""Prepare three explicitly scoped local acceptance accounts through business APIs.

Requires DEVICE_READY_ADMIN_PASSWORD and DEVICE_READY_USER_PASSWORD. Never resets
existing passwords, sends SOS, or bypasses the authorization preview service.
Evidence/backups are written outside Git under the repository output directory.
"""
import json
import os
import pathlib
import subprocess
import urllib.error
import urllib.request
import uuid

BASE = 'http://127.0.0.1:18084'
ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = ROOT / 'output' / 'device-ready' / 'accounts'
DOCKER = r'C:\Users\19221\AppData\Local\Programs\DockerDesktop\resources\bin\docker.exe'
PASSWORD = os.environ['DEVICE_READY_USER_PASSWORD']
SESSIONS = []


def request(path, body=None, token=None, expected=200):
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['X-Wearable-Token'] = token
    req = urllib.request.Request(BASE + path, headers=headers,
        data=json.dumps(body, ensure_ascii=False).encode() if body is not None else None)
    try:
        with urllib.request.urlopen(req, timeout=20) as response:
            status, output = response.status, response.read()
    except urllib.error.HTTPError as error:
        status, output = error.code, error.read()
    if status != expected:
        raise RuntimeError(f'{path}: expected {expected}, received {status}: {output.decode()}')
    return json.loads(output)


def login(name, password, admin=False):
    prefix = '/api/admin/v1' if admin else '/api/guardian/v1'
    result = request(prefix + ('/login' if admin else '/mobile/login'),
        {'username' if admin else 'account': name, 'password': password})
    SESSIONS.append((prefix, result['token']))
    return result


def save_json(name, value):
    (OUT / name).write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')


def main():
    assert len(PASSWORD) >= 8
    OUT.mkdir(parents=True, exist_ok=True)
    admin = login('admin', os.environ['DEVICE_READY_ADMIN_PASSWORD'], True)['token']
    state = request('/api/admin/v1/state', token=admin)['state']
    specs = [
        ('wear_user', '联调普通用户（周明）', 'person-1-2', ['mobile-user']),
        ('wear_peer', '联调普通用户（李志远）', 'person-1-1', ['mobile-user']),
        ('wear_duty', '联调值守员（陈建国）', 'person-1-0', ['duty', 'mobile-user']),
    ]
    for name, _, person_id, _ in specs:
        person = next(p for p in state['people'] if p['id'] == person_id)
        assert person['enabled'] and person['siteId'] == 'site-1'
        linked = next((a for a in state['accounts'] if a.get('personId') == person_id), None)
        assert linked is None or linked['loginName'] == name, 'Never replace another account/person link'
    backup = OUT / 'before.sql'
    if not backup.exists():
        dump = subprocess.run([DOCKER, 'exec', 'melhat-mysql', 'sh', '-c',
            'exec mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --single-transaction new-helmet'],
            check=True, capture_output=True).stdout
        assert len(dump) > 10000
        backup.write_bytes(dump)
        save_json('before-accounts.json', state)
    results = []
    for name, label, person_id, roles in specs:
        state = request('/api/admin/v1/state', token=admin)['state']
        account = next((a for a in state['accounts'] if a['loginName'] == name), None)
        bindings = [{'roleId': role, 'siteIds': ['site-1'], 'areaIds': '*'} for role in roles]
        data = {'name': label, 'loginName': name, 'personId': person_id, 'bindings': []}
        if account is None:
            created = request('/api/admin/v1/execute', {'type': 'accounts.create', 'input': {
                'siteId': 'site-1', 'operationId': str(uuid.uuid4()),
                'data': dict(data, password=PASSWORD)}}, admin)
            account = created['data']
        assert account['personId'] == person_id and account['name'] == label and account['enabled']
        if not account.get('roleIds'):
            data['bindings'] = bindings
            command = {'siteId': 'site-1', 'id': account['id'],
                'expectedVersion': account['version'], 'operationId': str(uuid.uuid4()), 'data': data}
            preview = request('/api/admin/v1/query', {'kind': 'authorizationPreview', 'input': {
                'siteId': 'site-1', 'type': 'accounts.update', 'command': command}}, admin)['data']
            account = request('/api/admin/v1/execute', {'type': 'accounts.update',
                'input': dict(command, previewId=preview['previewId'])}, admin)['data']
        assert set(account['roleIds']) == set(roles)
        for role in roles:
            assert account['roleScopes'][role] == {'siteIds': ['site-1'], 'areaIds': '*'}
        mobile = login(name, PASSWORD)
        identity = mobile['identity']
        assert identity['ledgerPersonId'] == person_id
        assert [s['id'] for s in identity['sites']] == ['site-1']
        token = mobile['token']
        request('/api/guardian/v1/mobile/home?siteId=site-2', token=token, expected=403)
        if roles == ['mobile-user']:
            rows = request('/api/guardian/v1/mobile/people?siteId=site-1', token=token)['rows']
            assert [p['id'] for p in rows] == [identity['personId']]
            other = 'P2' if identity['personId'] != 'P2' else 'P3'
            request(f'/api/guardian/v1/mobile/people/{other}?siteId=site-1', token=token, expected=404)
            request('/api/admin/v1/login', {'username': name, 'password': PASSWORD}, expected=403)
        else:
            pc = request('/api/guardian/v1/login', {'account': name, 'password': PASSWORD})
            SESSIONS.append(('/api/guardian/v1', pc['token']))
        results.append({'loginName': name, 'name': label, 'personId': identity['personId'],
            'roles': roles, 'sites': ['site-1'], 'loginVerified': True, 'scopeVerified': True})
    save_json('verified.json', results)
    save_json('after-accounts.json', request('/api/admin/v1/state', token=admin)['state'])
    print(json.dumps(results, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    try:
        main()
    finally:
        for prefix, token in SESSIONS:
            request(prefix + '/logout', {}, token)
