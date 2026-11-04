"""Generate (never execute) a narrowly guarded mobile-user scope repair.

Reads only fixed credential-free SELECT projections. Writes reviewable SQL and
sanitized evidence files. Apply/rollback require a quiesced backend: the existing
AdminLedgerStore can otherwise persist a stale whole-ledger snapshot after SQL CAS.
"""
import argparse
import datetime as dt
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[1]
ROLE = 'mobile-user'
EXPECTED_USERS = {'wear_user', 'wear_peer', 'wear_duty'}
EXPECTED_OPS = {'self:read', 'events:observe', 'sos:create', 'works:read'}
SQL = """SELECT JSON_OBJECT('kind','meta','data',JSON_OBJECT('revision',revision)) FROM wearable_meta WHERE id=1
UNION ALL SELECT JSON_OBJECT('kind','roles','data',JSON_OBJECT(
 'id',id,'name',name,'version',version,'enabled',JSON_EXTRACT(body,'$.enabled'),
 'bodyVersion',JSON_EXTRACT(body,'$.version'),'grants',JSON_EXTRACT(body,'$.grants'),
 'bodyHash',SHA2(body,256),'stableHash',SHA2(JSON_REMOVE(body,'$.grants','$.version','$.updatedAt'),256))) FROM wearable_role
UNION ALL SELECT JSON_OBJECT('kind','accounts','data',JSON_OBJECT(
 'id',id,'loginName',login_name,'version',version,'siteId',site_id,
 'bodySiteId',JSON_EXTRACT(body,'$.siteId'),'roleIds',JSON_EXTRACT(body,'$.roleIds')))
 FROM wearable_account WHERE JSON_CONTAINS(JSON_EXTRACT(body,'$.roleIds'),'"mobile-user"')
UNION ALL SELECT JSON_OBJECT('kind','sites','data',JSON_OBJECT('id',id,'enabled',enabled))
 FROM wearable_site WHERE id='site-1'
"""


def hex_text(value):
    # MySQL 8's default utf8mb4_0900_ai_ci differs from legacy unicode_ci columns.
    # An explicit binary collation has higher coercibility priority and keeps IDs exact.
    return "(CONVERT(0x" + value.encode('utf-8').hex() + " USING utf8mb4) COLLATE utf8mb4_bin)"


def json_expr(value):
    return 'CAST(' + hex_text(json.dumps(value, ensure_ascii=False, separators=(',', ':'))) + ' AS JSON)'


def read_snapshot(docker):
    args = [docker, 'exec', '-i', 'melhat-mysql', 'sh', '-c',
            'exec mysql --default-character-set=utf8mb4 -uroot -p"$MYSQL_ROOT_PASSWORD" -N -B -r "$1"',
            'station-scope-repair-plan', 'new-helmet']
    try:
        process = subprocess.run(args, input=SQL.encode(), capture_output=True, timeout=60)
    except (OSError, subprocess.TimeoutExpired):
        raise RuntimeError('Read-only repair planning query unavailable') from None
    if process.returncode:
        raise RuntimeError('Read-only repair planning query failed; no writes attempted')
    snapshot = dict(meta=[], roles=[], accounts=[], sites=[])
    for line in process.stdout.decode('utf-8').splitlines():
        row = json.loads(line)
        snapshot[row['kind']].append(row['data'])
    return snapshot


def validate(snapshot):
    roles = {row['id']: row for row in snapshot['roles']}
    role = roles.get(ROLE)
    if not role or not role['enabled'] or len(role['grants']) != 1:
        raise ValueError('Known enabled one-grant mobile-user role required')
    grant = role['grants'][0]
    if set(grant['operations']) != EXPECTED_OPS or set(grant['siteIds']) != {'site-1', 'site-2'}:
        raise ValueError('Role no longer matches the reviewed ordinary-user grant; re-audit')
    if role['version'] != role['bodyVersion']:
        raise ValueError('Role column/body versions disagree')
    accounts = snapshot['accounts']
    if len(accounts) != 3 or {x['loginName'] for x in accounts} != EXPECTED_USERS:
        raise ValueError('Role membership changed; review all affected accounts')
    if any(x['siteId'] != 'site-1' or x['bodySiteId'] != 'site-1' or ROLE not in x['roleIds'] for x in accounts):
        raise ValueError('Affected accounts no longer all belong to site-1')
    if len(snapshot['meta']) != 1 or not isinstance(snapshot['meta'][0]['revision'], int):
        raise ValueError('Ledger revision missing')
    if len(snapshot['sites']) != 1 or not snapshot['sites'][0]['enabled']:
        raise ValueError('Reviewed site-1 must remain enabled')
    for row in snapshot['roles']:
        if not re.fullmatch('[a-fA-F0-9]{64}', row['bodyHash']) or not re.fullmatch('[a-fA-F0-9]{64}', row['stableHash']):
            raise ValueError('Invalid role digest')
    return role


def conditions(snapshot, rollback=False):
    role = validate(snapshot)
    revision = snapshot['meta'][0]['revision'] + int(rollback)
    checks = [f'@observed_revision = {revision}',
              "(SELECT COUNT(*) FROM wearable_account WHERE JSON_CONTAINS(JSON_EXTRACT(body,'$.roleIds'),'\"mobile-user\"')) = 3",
              "EXISTS(SELECT 1 FROM wearable_site WHERE id='site-1' AND enabled=1)"]
    for account in snapshot['accounts']:
        checks.append("EXISTS(SELECT 1 FROM wearable_account WHERE id=" + hex_text(account['id']) +
                      " AND login_name=" + hex_text(account['loginName']) + " AND site_id='site-1' AND version=" + str(account['version']) +
                      " AND JSON_UNQUOTE(JSON_EXTRACT(body,'$.siteId'))='site-1' AND JSON_EXTRACT(body,'$.roleIds')=" + json_expr(account['roleIds']) + ')')
    others = [r for r in snapshot['roles'] if r['id'] != ROLE]
    checks.append("(SELECT COUNT(*) FROM wearable_role WHERE id<>'mobile-user')=" + str(len(others)))
    for other in others:
        checks.append('EXISTS(SELECT 1 FROM wearable_role WHERE id=' + hex_text(other['id']) +
                      " AND SHA2(body,256)='" + other['bodyHash'] + "' AND version=" + str(other['version']) + ')')
    return '\n AND '.join(checks)


def generate_sql(snapshot, operation_id, timestamp, rollback=False):
    role = validate(snapshot)
    old_grants = role['grants']
    new_grants = json.loads(json.dumps(old_grants))
    new_grants[0]['siteIds'] = ['site-1']
    before, after = (new_grants, old_grants) if rollback else (old_grants, new_grants)
    expected_version = role['version'] + int(rollback)
    next_version = expected_version + 1
    action = 'roles.scopeRollback' if rollback else 'roles.scopeNarrow'
    audit_id = operation_id + ('-rollback' if rollback else '-apply')
    event = dict(id=audit_id, siteId='site-1', actorId='system-maintenance', actorName='场站隔离维护',
                 action=action, objectId=ROLE, occurredAt=timestamp, result='SUCCESS', operationId=operation_id,
                 before=dict(id=ROLE, grants=before, version=expected_version),
                 after=dict(id=ROLE, grants=after, version=next_version),
                 source='Explicit reviewed SQL maintenance; backend quiesced; no credentials modified')
    guard = ("SHA2(JSON_REMOVE(body,'$.grants','$.version','$.updatedAt'),256)='" + role['stableHash'] +
             "' AND JSON_EXTRACT(body,'$.grants')=" + json_expr(new_grants)) if rollback else "SHA2(body,256)='" + role['bodyHash'] + "'"
    predicate = conditions(snapshot, rollback)
    return f"""-- GENERATED REVIEW PLAN ONLY. This script generator never executes writes.
-- REQUIRED: quiesce/stop the melhat-backend writer first; stale AdminLedgerStore snapshots can otherwise overwrite SQL changes.
-- Do not use mysql --force. An SQL error must abort the connection and roll back this transaction.
-- This transaction changes only mobile-user grants/version, one audit event, and ledger revision.
START TRANSACTION;
SELECT revision INTO @observed_revision FROM wearable_meta WHERE id=1 FOR UPDATE;
SELECT version INTO @observed_role_version FROM wearable_role WHERE id='mobile-user' FOR UPDATE;
SET @scope_repair_ready = ({predicate});
UPDATE wearable_role SET body=JSON_SET(body,'$.grants',{json_expr(after)},'$.version',{next_version},'$.updatedAt',{hex_text(timestamp)}),
 version={next_version}
 WHERE id='mobile-user' AND version={expected_version} AND {guard} AND @scope_repair_ready=1;
SET @scope_repair_changed = ROW_COUNT();
INSERT INTO wearable_audit (id,site_id,area_id,actor_id,object_id,action,result,occurred_at,sort_order,body)
 SELECT {hex_text(audit_id)},'site-1',NULL,'system-maintenance','mobile-user',{hex_text(action)},'SUCCESS',{hex_text(timestamp)},
 (SELECT COALESCE(MAX(a.sort_order),-1)+1 FROM wearable_audit a),{json_expr(event)}
 WHERE @scope_repair_changed=1;
UPDATE wearable_meta SET revision=revision+1 WHERE id=1 AND @scope_repair_changed=1;
SELECT IF(@scope_repair_changed=1,'APPLIED','CAS_CONFLICT_NO_CHANGES') AS result;
SELECT id,version,SHA2(body,256) AS bodyHash FROM wearable_role ORDER BY id;
COMMIT;
"""


def prepare(snapshot, output):
    role = validate(snapshot)
    output.mkdir(parents=True, exist_ok=False)
    operation_id = 'station-scope-' + uuid.uuid4().hex
    timestamp = dt.datetime.now(dt.timezone.utc).isoformat().replace('+00:00', 'Z')
    plan = dict(operationId=operation_id, preparedAtUtc=timestamp, executionPerformed=False,
                requiredExecutionCondition='Quiesce backend first; verify CAS result and non-target role hashes; restart/re-read afterwards.',
                targetRole=ROLE, targetSiteIds=['site-1'], expectedSnapshot=snapshot,
                retainedRoles='All roles except mobile-user unchanged, including auditor/system/duty.',
                rollback='Rollback intentionally restores the previous wider grant and requires explicit operator decision; refuses intervening ledger changes.')
    (output/'sanitized-plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    for name, rollback in [('apply.sql',False),('rollback.sql',True)]:
        (output/name).write_text(generate_sql(snapshot, operation_id, timestamp, rollback),encoding='utf-8')
    return dict(output=str(output), executionPerformed=False, targetRole=ROLE, affectedAccounts=[a['loginName'] for a in snapshot['accounts']])


class PlanTests(unittest.TestCase):
    def fixture(self):
        return dict(meta=[dict(revision=10)],sites=[dict(id='site-1',enabled=True)],
                    roles=[dict(id=ROLE,name='ordinary',version=2,bodyVersion=2,enabled=True,bodyHash='a'*64,stableHash='b'*64,
                                grants=[dict(operations=sorted(EXPECTED_OPS),siteIds=['site-1','site-2'])]),
                           dict(id='audit',name='upper',version=1,bodyVersion=1,enabled=True,bodyHash='c'*64,stableHash='d'*64,grants=[])],
                    accounts=[dict(id=name,loginName=name,version=1,siteId='site-1',bodySiteId='site-1',roleIds=[ROLE]+(['duty'] if name=='wear_duty' else [])) for name in sorted(EXPECTED_USERS)])

    def test_precise_narrowing_and_audit(self):
        sql=generate_sql(self.fixture(),'review','2026-11-04T00:00:00Z')
        self.assertIn('WHERE id=\'mobile-user\' AND version=2',sql)
        self.assertIn("SHA2(body,256)='"+'a'*64+"'",sql)
        self.assertIn('INSERT INTO wearable_audit',sql)
        self.assertNotIn('UPDATE wearable_account',sql)
        self.assertIn('CAS_CONFLICT_NO_CHANGES',sql)

    def test_preserves_all_non_target_roles(self):
        sql=generate_sql(self.fixture(),'review','date')
        self.assertIn('c'*64,sql)
        self.assertIn("WHERE id<>'mobile-user')=1",sql)

    def test_different_membership_or_home_site_rejected(self):
        state=self.fixture();state['accounts'][0]['siteId']='site-2'
        with self.assertRaises(ValueError):validate(state)
        state=self.fixture();state['accounts'].pop()
        with self.assertRaises(ValueError):validate(state)

    def test_legitimate_changed_role_is_not_overwritten(self):
        state=self.fixture();state['roles'][0]['grants'][0]['operations'].append('accounts:write')
        with self.assertRaises(ValueError):validate(state)

    def test_rollback_requires_exact_next_revision(self):
        sql=generate_sql(self.fixture(),'review','date',True)
        self.assertIn('@observed_revision = 11',sql)
        self.assertIn("WHERE id='mobile-user' AND version=3",sql)
        self.assertIn('b'*64,sql)

    def test_reader_is_select_only_without_credentials(self):
        for word in ('password','token','secret','update ','delete ','insert '):self.assertNotIn(word,SQL.lower())
        self.assertTrue(SQL.startswith('SELECT '))

    def test_generated_text_uses_explicit_exact_collation(self):
        expression=hex_text('site-1')
        self.assertIn('COLLATE utf8mb4_bin',expression)
        self.assertIn('736974652d31',expression)
        sql=generate_sql(self.fixture(),'review','date')
        self.assertIn("id=(CONVERT(0x",sql)
        self.assertNotIn('USING utf8mb4) AND',sql)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--docker',default='docker')
    parser.add_argument('--output',type=Path,default=ROOT/'output/station-isolation-20261104-current/mobile-role-repair-plan')
    parser.add_argument('--self-test',action='store_true')
    args=parser.parse_args()
    if args.self_test:
        result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(PlanTests))
        raise SystemExit(0 if result.wasSuccessful() else 1)
    print(json.dumps(prepare(read_snapshot(args.docker),args.output),ensure_ascii=False))


if __name__=='__main__':main()
