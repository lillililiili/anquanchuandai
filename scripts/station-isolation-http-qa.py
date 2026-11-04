"""Station isolation acceptance against a disposable Docker clone only.

Fresh passwords are installed only in cloned accounts. Never reads live passwords,
publishes ports, sends device commands, or authenticates to the daily service.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[1]
BACKEND = ROOT / '后端代码/melhat_server-dev'
spec = importlib.util.spec_from_file_location('qa', BACKEND / 'local-dev/wearable-compatible-qa.py')
qa = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qa)
patch = qa.patch
plan_spec = importlib.util.spec_from_file_location('planner', ROOT / 'scripts/plan-station-scope-repair.py')
planner = importlib.util.module_from_spec(plan_spec)
plan_spec.loader.exec_module(planner)


def run(directory, repair):
    directory = Path(directory).resolve()
    if directory.parent != BACKEND / 'build':
        raise RuntimeError('Expected workspace QA build directory')
    resources = patch.read_json(directory / 'qa-resources.json')
    smoke = patch.read_json(directory / 'qa-anonymous-smoke.json')
    backend, mysql = resources['backend'], resources['mysql']
    if not smoke['passed'] or not backend.startswith('wearable-compatible-qa-') or not mysql.startswith('wearable-compatible-qa-'):
        raise RuntimeError('Only a verified disposable clone is supported')
    original = patch.inspect(backend)
    network = json.loads(patch.docker('network', 'inspect', resources['network']))[0]
    if original['Image'] != smoke['imageId'] or not network['Internal'] or original['HostConfig']['PortBindings']:
        raise RuntimeError('Clone isolation preconditions failed')
    daily = patch.inspect('melhat-backend')
    evidence = dict(passed=False, checks=[], requests=[], liveAuthenticated=False, productionWrites=False,
                    passwordChangesScope='disposable clone only', imageId=original['Image'], jarSha256=smoke['jarSha256'])
    private = directory / 'qa-private'
    password = secrets.token_urlsafe(24)
    libraries = Path.home() / '.m2/repository'
    crypto = sorted(libraries.glob('org/springframework/security/spring-security-crypto/*/*.jar'))[-1]
    logging = sorted(libraries.glob('org/springframework/spring-jcl/*/*.jar'))[-1]
    cp = os.pathsep.join(map(str, [crypto, logging]))
    source = private / 'StationQaHash.java'
    source.write_text('import java.io.*; import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder; '
                      'public class StationQaHash { public static void main(String[] a)throws Exception { '
                      'System.out.print(new BCryptPasswordEncoder().encode(new BufferedReader(new InputStreamReader(System.in)).readLine())); }}', encoding='utf-8')
    subprocess.run([shutil.which('javac'), '-cp', cp, str(source)], check=True, capture_output=True)
    digest = subprocess.run([shutil.which('java'), '-cp', str(private) + os.pathsep + cp, 'StationQaHash'],
                            input=password.encode(), check=True, capture_output=True).stdout.decode()
    if not digest.startswith('$2'):
        raise RuntimeError('Clone credential preparation failed')
    patch.docker('stop', '--time', '30', backend)
    try:
        plan = patch.read_json(Path(repair).parent / 'sanitized-plan.json')
        original_role = planner.validate(plan['expectedSnapshot'])
        grants = json.loads(json.dumps(original_role['grants']))
        grants[0]['siteIds'] = ['site-1']
        guard = ("SELECT JSON_OBJECT('matches',COUNT(*)) FROM wearable_role WHERE id='mobile-user' AND version="
                 + str(original_role['version'] + 1) + " AND JSON_EXTRACT(body,'$.grants')=" + planner.json_expr(grants)
                 + " AND SHA2(JSON_REMOVE(body,'$.grants','$.version','$.updatedAt'),256)='" + original_role['stableHash']
                 + "' AND EXISTS(SELECT 1 FROM wearable_audit WHERE id=" + planner.hex_text(plan['operationId'] + '-apply') + ');')
        matched = json.loads(qa.clone_sql(mysql, guard.encode()).decode().splitlines()[-1])['matches'] == 1
        if not matched:
            result = qa.clone_sql(mysql, Path(repair).read_bytes()).decode()
            if 'APPLIED' not in result or 'CAS_CONFLICT' in result:
                raise RuntimeError('Clone role repair CAS rejected the snapshot')
        evidence['checks'].append('reviewed-role-repair-applied-on-clone')
        sql = "UPDATE wearable_account SET body=JSON_SET(body,'$.passwordHash','" + digest + "') WHERE login_name IN ('wear_user','wear_peer','wear_duty','siteadmin','auditor','admin');"
        qa.clone_sql(mysql, sql.encode())
    finally:
        patch.docker('start', backend)
    previous = patch.LIVE
    try:
        patch.LIVE = backend
        patch.anonymous_health()
    finally:
        patch.LIVE = previous

    def request(method, path, body=None, token=None, expected=200):
        config = ['url = ' + json.dumps('http://127.0.0.1:18084' + path),
                  'request = ' + json.dumps(method), 'header = "Content-Type: application/json"']
        if token:
            config.append('header = ' + json.dumps('X-Wearable-Token: ' + token))
        if body is not None:
            config.append('data = ' + json.dumps(json.dumps(body, ensure_ascii=False), ensure_ascii=False))
        raw = patch.docker('exec', '-i', backend, 'curl', '--silent', '--show-error', '--max-time', '30',
                           '--write-out', '\n%{http_code}', '--config', '-', data=('\n'.join(config) + '\n').encode()).decode()
        payload, code = raw.rsplit('\n', 1)
        code = int(code)
        parsed = json.loads(payload) if payload else {}
        item = dict(method=method, path=path, status=code)
        if code != expected:
            item['errorCode'] = parsed.get('errorCode')
            item['message'] = parsed.get('message')
        evidence['requests'].append(item)
        if code != expected:
            raise RuntimeError(f'Unexpected HTTP status for {method} {path}: {code}, expected {expected}, error={parsed.get("errorCode")}')
        return parsed

    try:
        for name in ('wear_user', 'wear_peer'):
            denied = request('POST', '/api/guardian/v1/mobile/login', dict(account=name, password=password), expected=403)
            if denied.get('errorCode') != 'PERSON_REQUIRED':
                raise RuntimeError('Unlinked ordinary account must fail closed before issuing a session')
        evidence['checks'].append('existing-unlinked-wear-user-and-peer-cannot-login')
        tokens = {}
        for name in ('siteadmin', 'auditor', 'admin'):
            tokens[name] = request('POST', '/api/admin/v1/login', dict(username=name, password=password))['token']
        suffix = uuid.uuid4().hex[:10]
        def create(token, site, expected):
            return request('POST', '/api/admin/v1/execute', dict(type='people.create', input=dict(
                siteId=site, operationId=str(uuid.uuid4()), data=dict(name='隔离验证人员', code='ISO-' + suffix + '-' + site,
                remark='仅隔离数据库测试'))), token, expected)
        fixture_person = create(tokens['admin'], 'site-1', 200)['data']
        fixture_name = 'iso-mobile-' + suffix
        request('POST', '/api/admin/v1/execute', dict(type='accounts.create', input=dict(
            siteId='site-1', operationId=str(uuid.uuid4()), relatedVersions={fixture_person['id']:fixture_person['version']},
            data=dict(name='隔离普通用户',loginName=fixture_name,password=password,personId=fixture_person['id'],
                      bindings=[dict(roleId='mobile-user')]))), tokens['admin'])
        for name in (fixture_name, 'wear_duty'):
            login = request('POST', '/api/guardian/v1/mobile/login', dict(account=name, password=password))
            token = login['token']
            identity = request('GET', '/api/guardian/v1/mobile/identity', token=token)
            if {row['id'] for row in identity['sites']} != {'site-1'}:
                raise RuntimeError('Ordinary account has unexpected station grants: ' + name)
            request('GET', '/api/guardian/v1/mobile/context?siteId=site-1', token=token)
            request('GET', '/api/guardian/v1/mobile/context?siteId=site-2', token=token, expected=403)
            request('GET', '/hat/safetyHatInfo/list', token=token, expected=410)
        evidence['checks'].append('linked-ordinary-fixture-and-existing-wear-duty-only-home-station')
        def query(token, kind, site=None, expected=200):
            values = {} if site is None else dict(siteId=site)
            if kind == 'people':
                kind = 'master'
                values['entity'] = 'people'
            return request('POST', '/api/admin/v1/query', dict(kind=kind, input=values), token, expected)
        context = query(tokens['siteadmin'], 'context')['data']
        if {s['id'] for s in context['sites']} != {'site-1'}:
            raise RuntimeError('Site manager scope expanded')
        query(tokens['siteadmin'], 'people', 'site-1')
        query(tokens['siteadmin'], 'people', 'site-2', 403)
        query(tokens['auditor'], 'people', 'site-1')
        query(tokens['auditor'], 'people', 'site-2')
        suffix = uuid.uuid4().hex[:10]
        create(tokens['siteadmin'], 'site-1', 200)
        create(tokens['siteadmin'], 'site-2', 403)
        create(tokens['auditor'], 'site-2', 403)
        create(tokens['admin'], 'site-2', 200)
        evidence['checks'].append('site-manager-local-write-foreign-denied-auditor-cross-site-read-only-system-write-authorized')
        for path in ('/login', '/system/user/list', '/common/download', '/ws/probe', '/ext/notifyGnss'):
            request('POST' if path in ('/login', '/ext/notifyGnss') else 'GET', path, token=tokens['admin'], expected=410)
        evidence['checks'].append('retired-routes-remain-closed-with-authenticated-admin-token')
        after = patch.inspect('melhat-backend')
        if after['Id'] != daily['Id'] or after['Image'] != daily['Image'] or not after['State']['Running']:
            raise RuntimeError('Daily backend changed during QA')
        evidence.update(passed=True, dailyContainerUnchanged=True, completedAt=patch.now())
    finally:
        patch.write_json(directory / 'station-isolation-http-qa.json', evidence)
    return evidence


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', required=True)
    parser.add_argument('--repair', required=True)
    args = parser.parse_args()
    result = run(args.directory, args.repair)
    print(json.dumps(dict(passed=result['passed'], checks=result['checks'], requests=len(result['requests'])), ensure_ascii=False))
