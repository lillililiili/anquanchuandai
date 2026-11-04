"""Read-only station authorization audit; projects no credentials from the database.

Usage: python scripts/station-authorization-audit.py [--docker PATH]
       python scripts/station-authorization-audit.py --self-test

This reports configured enabled role grants, without inferring the deployed code
version. Patched Guardian mobile-user access also intersects the account's home.
Cross-site management grants are review items, never automatically changed.
"""
import argparse
import datetime as dt
import json
import pathlib
import re
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = ROOT / 'output/station-isolation-20261104-current/authorization-audit.json'

# Explicit projections are intentional. Never SELECT body, password, passwordHash,
# access token, credential material, or container environment into this process.
SQL = """SELECT JSON_OBJECT('kind','accounts','data',JSON_OBJECT(
  'id',id,'loginName',login_name,'siteId',site_id,'personId',person_id,
  'enabled',JSON_EXTRACT(body,'$.enabled'),'roleIds',JSON_EXTRACT(body,'$.roleIds'),
  'bodySiteId',JSON_EXTRACT(body,'$.siteId'),'bodyPersonId',JSON_EXTRACT(body,'$.personId'))) FROM wearable_account
UNION ALL SELECT JSON_OBJECT('kind','roles','data',JSON_OBJECT(
  'id',id,'name',name,'enabled',JSON_EXTRACT(body,'$.enabled'),
  'grants',JSON_EXTRACT(body,'$.grants'))) FROM wearable_role
UNION ALL SELECT JSON_OBJECT('kind','sites','data',JSON_OBJECT(
  'id',id,'name',name,'enabled',JSON_EXTRACT(body,'$.enabled'))) FROM wearable_site
UNION ALL SELECT JSON_OBJECT('kind','people','data',JSON_OBJECT(
  'id',id,'siteId',site_id,'accountId',account_id,
  'enabled',JSON_EXTRACT(body,'$.enabled'))) FROM wearable_person
UNION ALL SELECT JSON_OBJECT('kind','legacyUsers','data',JSON_OBJECT(
  'userId',user_id,'loginName',user_name,'deptId',dept_id,
  'enabled',status='0','deleted',del_flag<>'0')) FROM sys_user
"""


def enabled(value):
    return value is True or value == 1


def strings(value):
    return [item for item in value if isinstance(item, str)] if isinstance(value, list) else []


def resolve_account(account, roles, sites, people):
    findings = []

    def finding(code, **detail):
        findings.append(dict(code=code, **detail))

    active = enabled(account.get('enabled'))
    system = active and account.get('id') == 'demo-system'
    own_site = account.get('siteId')
    site = sites.get(own_site)
    if site is None:
        finding('ACCOUNT_SITE_UNKNOWN', siteId=own_site)
    elif not enabled(site.get('enabled')):
        finding('ACCOUNT_SITE_DISABLED', siteId=own_site)
    if 'bodySiteId' in account and account.get('bodySiteId') != own_site:
        finding('ACCOUNT_SITE_COLUMN_BODY_MISMATCH', bodySiteId=account.get('bodySiteId'))

    person_id = account.get('bodyPersonId') if 'bodyPersonId' in account else account.get('personId')
    if 'bodyPersonId' in account and (account.get('bodyPersonId') or None) != (account.get('personId') or None):
        finding('ACCOUNT_PERSON_COLUMN_BODY_MISMATCH', columnPersonId=account.get('personId'), bodyPersonId=account.get('bodyPersonId'))
    if active and set(strings(account.get('roleIds'))) == {'mobile-user'} and not person_id:
        finding('ORDINARY_ACCOUNT_PERSON_REQUIRED')
    if person_id:
        person = people.get(person_id)
        if person is None:
            finding('LINKED_PERSON_UNKNOWN', personId=person_id)
        else:
            if person.get('siteId') != own_site:
                finding('LINKED_PERSON_SITE_MISMATCH', personId=person_id, personSiteId=person.get('siteId'))
            if not enabled(person.get('enabled')):
                finding('LINKED_PERSON_DISABLED', personId=person_id)
            if person.get('accountId') not in (None, '', account.get('id')):
                finding('LINKED_PERSON_ACCOUNT_MISMATCH', personId=person_id)

    assigned_roles, effective = [], {}
    for role_id in strings(account.get('roleIds')):
        role = roles.get(role_id)
        if role is None:
            finding('UNKNOWN_ROLE', roleId=role_id)
            assigned_roles.append(dict(id=role_id, enabled=False, missing=True))
            continue
        role_active = enabled(role.get('enabled'))
        assigned_roles.append(dict(id=role_id, name=role.get('name'), enabled=role_active))
        if not role_active:
            finding('DISABLED_ROLE', roleId=role_id)
            continue
        for grant in role.get('grants') or []:
            if not isinstance(grant, dict):
                finding('MALFORMED_GRANT', roleId=role_id)
                continue
            operations = strings(grant.get('operations'))
            for site_id in strings(grant.get('siteIds')):
                granted_site = sites.get(site_id)
                if granted_site is None:
                    finding('GRANT_SITE_UNKNOWN', roleId=role_id, siteId=site_id)
                    continue
                if not enabled(granted_site.get('enabled')):
                    finding('GRANT_SITE_DISABLED', roleId=role_id, siteId=site_id)
                    continue
                if active and operations:
                    effective.setdefault(site_id, set()).update(operations)

    cross_sites = sorted(set(effective) - {own_site})
    if cross_sites:
        finding('REVIEW_CROSS_STATION_GRANT', siteIds=cross_sites,
                interpretation='May be intentional upper-level authorization; do not auto-narrow.')
    management_operations = {'*', 'roles:write', 'accounts:write', 'sites:write', 'organization:write'}
    management_sites = sorted(site_id for site_id, ops in effective.items() if ops & management_operations)
    if active and not system and not effective:
        finding('NO_EFFECTIVE_SITE_GRANT')
    return dict(id=account.get('id'), loginName=account.get('loginName'), siteId=own_site,
                enabled=active, linkedPersonId=person_id, roles=assigned_roles,
                effectiveOperationsBySite={key: sorted(effective[key]) for key in sorted(effective)},
                systemAdministratorOverride=system,
                systemAdministratorEnabledSiteIds=sorted(key for key, value in sites.items() if enabled(value.get('enabled'))) if system else [],
                crossStationRoleAuthorization=bool(cross_sites),
                managementGrantSiteIds=management_sites, findings=findings)


def audit(snapshot):
    index = lambda key: {item['id']: item for item in snapshot.get(key, [])}
    roles, sites, people = index('roles'), index('sites'), index('people')
    accounts = [resolve_account(item, roles, sites, people) for item in snapshot.get('accounts', [])]
    legacy = [{key: row.get(key) for key in ('userId', 'loginName', 'deptId', 'enabled', 'deleted')}
              for row in snapshot.get('legacyUsers', [])]
    legacy_active = [row for row in legacy if enabled(row.get('enabled')) and not enabled(row.get('deleted'))]
    return dict(readOnly=True, scope='Current wearable role grants; no account or role changes',
                limitations=['SQL snapshot is not a login/API penetration test.',
                             'Reports configured role grants. Patched Guardian mobile-user access also intersects its trusted home site; management roles retain explicit grants. Deployment is verified separately.',
                             'Disabled site grants are reported but excluded from normal business access; sites:write is a management exception.',
                             'Legacy user existence does not prove a legacy route is accessible.'],
                accounts=accounts, sites=list(sites.values()), roles=list(roles.values()), legacyUsers=legacy,
                summary=dict(accounts=len(accounts), enabledAccounts=sum(item['enabled'] for item in accounts),
                             accountsWithFindings=sum(bool(item['findings']) for item in accounts),
                             crossStationRoleAccounts=sum(item['crossStationRoleAuthorization'] for item in accounts),
                             enabledLegacyUsers=len(legacy_active)))


def query_snapshot(docker, container, database):
    if not re.fullmatch(r'[A-Za-z0-9_.-]+', container) or not re.fullmatch(r'[A-Za-z0-9_-]+', database):
        raise ValueError('Invalid container/database identifier')
    command = [docker, 'exec', '-i', container, 'sh', '-c',
               'exec mysql --default-character-set=utf8mb4 -uroot -p"$MYSQL_ROOT_PASSWORD" -N -B -r "$1"',
               'station-authorization-audit', database]
    try:
        result = subprocess.run(command, input=SQL.encode('utf-8'), stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=60)
    except (OSError, subprocess.TimeoutExpired):
        raise RuntimeError('Read-only database query unavailable; no database writes attempted') from None
    if result.returncode:
        raise RuntimeError('Read-only database query failed; no database writes attempted')
    snapshot = {key: [] for key in ('accounts', 'roles', 'sites', 'people', 'legacyUsers')}
    for line in result.stdout.decode('utf-8').splitlines():
        row = json.loads(line)
        snapshot[row['kind']].append(row['data'])
    return snapshot


class ResolutionTests(unittest.TestCase):
    def setUp(self):
        self.sites = {'s1': dict(id='s1', enabled=True), 's2': dict(id='s2', enabled=True), 'off': dict(id='off', enabled=False)}
        self.roles = {'local': dict(id='local', enabled=True, grants=[dict(siteIds=['s1'], operations=['assets:read'])]),
                      'upper': dict(id='upper', enabled=True, grants=[dict(siteIds=['s1', 's2'], operations=['assets:read', 'accounts:write'])]),
                      'disabled': dict(id='disabled', enabled=False, grants=[dict(siteIds=['s2'], operations=['*'])])}
        self.account = dict(id='a', loginName='local', siteId='s1', enabled=True, roleIds=['local'])

    def resolve(self):
        return resolve_account(self.account, self.roles, self.sites, {})

    def test_local_account_has_only_local_operations(self):
        self.assertEqual(self.resolve()['effectiveOperationsBySite'], {'s1': ['assets:read']})
        self.assertFalse(self.resolve()['crossStationRoleAuthorization'])

    def test_upper_grants_are_preserved_for_review(self):
        self.account['roleIds'] = ['upper']
        result = self.resolve()
        self.assertEqual(set(result['effectiveOperationsBySite']), {'s1', 's2'})
        self.assertEqual(result['managementGrantSiteIds'], ['s1', 's2'])
        self.assertEqual(result['findings'][0]['code'], 'REVIEW_CROSS_STATION_GRANT')

    def test_disabled_account_is_denied(self):
        self.account['enabled'] = False
        self.assertEqual(self.resolve()['effectiveOperationsBySite'], {})

    def test_disabled_and_missing_roles_do_not_grant(self):
        self.account['roleIds'] = ['disabled', 'missing']
        result = self.resolve()
        self.assertEqual(result['effectiveOperationsBySite'], {})
        self.assertEqual({x['code'] for x in result['findings']}, {'DISABLED_ROLE', 'UNKNOWN_ROLE', 'NO_EFFECTIVE_SITE_GRANT'})

    def test_unknown_or_disabled_site_is_not_business_scope(self):
        self.roles['local']['grants'][0]['siteIds'] = ['missing', 'off']
        self.assertEqual(self.resolve()['effectiveOperationsBySite'], {})

    def test_linked_person_must_match_home_site(self):
        self.account['personId'] = 'p'
        result = resolve_account(self.account, self.roles, self.sites, {'p': dict(id='p', siteId='s2', accountId='a', enabled=True)})
        self.assertIn('LINKED_PERSON_SITE_MISMATCH', [x['code'] for x in result['findings']])

    def test_system_override_explicit_not_simulated_grant(self):
        self.account.update(id='demo-system', roleIds=[])
        result = self.resolve()
        self.assertTrue(result['systemAdministratorOverride'])
        self.assertEqual(result['systemAdministratorEnabledSiteIds'], ['s1', 's2'])
        self.assertEqual(result['effectiveOperationsBySite'], {})

    def test_ordinary_mobile_account_requires_linked_person(self):
        self.account['roleIds']=['mobile-user']
        self.roles['mobile-user']=dict(id='mobile-user',enabled=True,grants=[dict(siteIds=['s1'],operations=['self:read'])])
        self.assertIn('ORDINARY_ACCOUNT_PERSON_REQUIRED',[item['code'] for item in self.resolve()['findings']])

    def test_manager_or_disabled_account_not_misclassified_as_unbound_ordinary(self):
        self.account['roleIds']=['upper','mobile-user']
        self.assertNotIn('ORDINARY_ACCOUNT_PERSON_REQUIRED',[item['code'] for item in self.resolve()['findings']])
        self.account.update(roleIds=['mobile-user'],enabled=False)
        self.assertNotIn('ORDINARY_ACCOUNT_PERSON_REQUIRED',[item['code'] for item in self.resolve()['findings']])

    def test_body_person_identity_is_authoritative_and_disagreement_reported(self):
        self.account.update(roleIds=['mobile-user'],personId='column-person',bodyPersonId=None)
        result=self.resolve()
        codes={item['code'] for item in result['findings']}
        self.assertIn('ACCOUNT_PERSON_COLUMN_BODY_MISMATCH',codes)
        self.assertIn('ORDINARY_ACCOUNT_PERSON_REQUIRED',codes)
        self.assertIsNone(result['linkedPersonId'])

    def test_sql_projects_no_sensitive_fields(self):
        self.assertTrue(SQL.startswith('SELECT '))
        for forbidden in ['password', 'token', 'SELECT body', 'UPDATE ', 'DELETE ', 'INSERT ', 'ALTER ', 'DROP ']:
            self.assertNotIn(forbidden.lower(), SQL.lower())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--docker', default=shutil.which('docker') or 'docker')
    parser.add_argument('--container', default='melhat-mysql')
    parser.add_argument('--database', default='new-helmet')
    parser.add_argument('--output', type=pathlib.Path, default=DEFAULT_OUTPUT)
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    if args.self_test:
        result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(ResolutionTests))
        raise SystemExit(0 if result.wasSuccessful() else 1)
    report = audit(query_snapshot(args.docker, args.container, args.database))
    report['capturedAtUtc'] = dt.datetime.now(dt.timezone.utc).isoformat()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(dict(output=str(args.output), readOnly=True, summary=report['summary']), ensure_ascii=False))


if __name__ == '__main__':
    main()
