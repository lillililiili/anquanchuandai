"""Explicit compatible rollout of the reviewed station-isolation candidate.

Default is validation only. --apply is mandatory for service/database mutations.
No role widening or database restoration is performed on failure: the predecessor
container is recovered against current SQL, retaining a committed scope reduction.
"""
import argparse
import datetime as dt
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch as mock_patch

ROOT = Path(__file__).resolve().parents[1]
BACKEND = ROOT / '后端代码/melhat_server-dev'
BUILD = BACKEND / 'build'


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


helpers = load('station_deploy_helpers', BACKEND / 'local-dev/wearable-container-patch.py')
planner = load('station_repair_planner', ROOT / 'scripts/plan-station-scope-repair.py')
builder = load('station_candidate_builder', ROOT / 'scripts/build-station-isolation-candidate.py')


def read_json(path): return json.loads(path.read_text(encoding='utf-8'))
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def authorization_snapshot():
    statement = """SELECT JSON_OBJECT('roles',(SELECT JSON_ARRAYAGG(JSON_OBJECT(
      'id',id,'version',version,'bodyHash',SHA2(body,256),
      'stableHash',SHA2(JSON_REMOVE(body,'$.grants','$.version','$.updatedAt'),256),
      'grants',JSON_EXTRACT(body,'$.grants'))) FROM wearable_role),
      'accounts',(SELECT JSON_ARRAYAGG(JSON_OBJECT('id',id,'version',version,
      'bodyHash',SHA2(body,256))) FROM wearable_account),
      'revision',(SELECT revision FROM wearable_meta WHERE id=1))"""
    return json.loads(helpers.read_sql(statement))


def validate_evidence(release, smoke, http):
    if not release.get('unchangedNonTaskEntriesVerified'):
        raise ValueError('Candidate non-task preservation evidence missing')
    if release.get('publicProtectedCompatibilityWarnings'):
        raise ValueError('Candidate has unresolved binary compatibility warnings')
    for evidence in (smoke, http):
        if evidence.get('passed') is not True or evidence.get('dailyContainerUnchanged') is not True:
            raise ValueError('Isolated acceptance evidence missing or daily state changed')
        if evidence.get('jarSha256') != release.get('jarSha256'):
            raise ValueError('Acceptance evidence targets a different JAR')
    if smoke.get('loginAttempted') is not False:
        raise ValueError('Anonymous smoke must not authenticate')
    if http.get('productionWrites') is not False:
        raise ValueError('HTTP acceptance touched production or lacks that assertion')
    if not smoke.get('imageId') or smoke['imageId'] != http.get('imageId'):
        raise ValueError('Acceptance evidence targets different images')


def validate_jar(release_dir, manifest):
    before_path, after_path = release_dir/'baseline-fdc-admin.jar', release_dir/'fdc-admin.jar'
    if digest(before_path) != manifest['baselineJarSha256'] or digest(after_path) != manifest['jarSha256']:
        raise ValueError('Candidate/baseline file hash mismatch')
    before, after = builder.entries(before_path.read_bytes()), builder.entries(after_path.read_bytes())
    libraries = {'BOOT-INF/lib/'+module+'-3.8.5.jar':module for module in builder.ALLOW if module!='ruoyi-admin'}
    for name in set(before)|set(after):
        if before.get(name)==after.get(name):continue
        if name in libraries:
            if name not in before or name not in after:raise ValueError('Nested library added/removed')
            module=libraries[name]
            old,new=builder.entries(before[name]),builder.entries(after[name])
            for entry in set(old)|set(new):
                if old.get(entry)!=new.get(entry) and not builder.allowed(module,entry):
                    raise ValueError('Candidate changes an unlisted nested entry')
        elif name.startswith('BOOT-INF/classes/'):
            entry=name[len('BOOT-INF/classes/'):]
            if entry not in builder.RESOURCES and not builder.allowed('ruoyi-admin',entry):
                raise ValueError('Candidate changes an unlisted application entry')
        else:raise ValueError('Candidate changes an unlisted outer entry')


def verify_plan(directory):
    plan=read_json(directory/'sanitized-plan.json')
    planner.validate(plan['expectedSnapshot'])
    expected=planner.generate_sql(plan['expectedSnapshot'],plan['operationId'],plan['preparedAtUtc'])
    actual=(directory/'apply.sql').read_text(encoding='utf-8')
    if actual!=expected:raise ValueError('Repair SQL differs from the exact narrow-scope generator output')
    if plan.get('targetRole')!='mobile-user' or plan.get('targetSiteIds')!=['site-1']:
        raise ValueError('Only the reviewed mobile-user/site-1 narrowing is supported')
    return plan,actual.encode('utf-8')


def validate_plan_state(plan, observed):
    expected=plan['expectedSnapshot']
    if observed['revision'] != expected['meta'][0]['revision']:
        raise ValueError('Live ledger revision changed; regenerate the repair plan')
    role_hashes=lambda data:{row['id']:row['bodyHash'] for row in data}
    if role_hashes(observed['roles'])!=role_hashes(expected['roles']):
        raise ValueError('Live role content changed; regenerate the repair plan')


def verify_authorization(before, after, plan):
    key=lambda rows:{row['id']:row for row in rows}
    old,new=key(before['roles']),key(after['roles'])
    if set(old)!=set(new):raise RuntimeError('Role inventory changed')
    for role_id in old:
        if role_id!='mobile-user' and old[role_id]['bodyHash']!=new[role_id]['bodyHash']:
            raise RuntimeError('Non-target role changed: '+role_id)
    if key(before['accounts'])!=key(after['accounts']):raise RuntimeError('Account documents changed')
    target=new['mobile-user'];original=old['mobile-user']
    grants=json.loads(json.dumps(original['grants']));grants[0]['siteIds']=['site-1']
    if target['version']!=original['version']+1 or target['grants']!=grants or target['stableHash']!=original['stableHash']:
        raise RuntimeError('Target role differs from the precise planned reduction')
    if after['revision']<before['revision']+1:raise RuntimeError('Ledger revision did not advance')


def single_writer(previous):
    networks=list(previous['NetworkSettings']['Networks'])
    if len(networks)!=1:raise RuntimeError('Expected one daily deployment network')
    ids=helpers.docker('ps','--filter','network='+networks[0],'--format','{{.ID}}').decode().splitlines()
    for ident in ids:
        item=helpers.inspect(ident)
        if item['Id']==previous['Id']:continue
        labels=item['Config'].get('Labels') or {}
        args=' '.join(item['Config'].get('Cmd') or [])
        if labels.get('com.docker.compose.service')=='backend' or 'spring.datasource' in args:
            raise RuntimeError('Another backend writer shares the daily database network')


def sql_apply(data):
    result=helpers.docker('exec','-i',helpers.MYSQL,'sh','-c',
        'exec mysql --default-character-set=utf8mb4 -uroot -p"$MYSQL_ROOT_PASSWORD" -N -B -r "$1"',
        'station-isolation-reviewed-repair',helpers.DATABASE,data=data,timeout=60).decode('utf-8')
    if result.splitlines()[0:1]!=['APPLIED'] or 'CAS_CONFLICT' in result:
        raise RuntimeError('Role repair CAS did not apply; no widening attempted')


def retired_checks():
    results={}
    for path in ('/login','/captchaImage','/hat/safety/info/list','/system/user/list','/ws/probe/1','/profile/probe'):
        code=helpers.docker('exec',helpers.LIVE,'curl','--silent','--max-time','5','--output','/dev/null',
                           '--write-out','%{http_code}','http://127.0.0.1:18084'+path).decode()
        if code!='410':raise RuntimeError('Retired endpoint did not reject: '+path)
        results[path]=410
    return results


def preflight(release_dir,qa_dir,plan_dir):
    for path in (release_dir,qa_dir):
        if path.parent!=BUILD:raise ValueError('Release/QA directory must be directly below backend/build')
    if not plan_dir.is_relative_to(ROOT/'output'):raise ValueError('Repair plan must be in workspace output')
    release=read_json(release_dir/'release.json')
    smoke=read_json(qa_dir/'qa-anonymous-smoke.json')
    http=read_json(qa_dir/'station-isolation-http-qa.json')
    validate_evidence(release,smoke,http);validate_jar(release_dir,release)
    plan,sql=verify_plan(plan_dir)
    previous=helpers.inspect(helpers.LIVE);target=helpers.inspect(smoke['imageId'])
    if not previous['State']['Running']:raise RuntimeError('Daily backend must be running before preflight')
    running=helpers.docker('exec',helpers.LIVE,'sha256sum','/app/fdc-admin.jar').decode().split()[0]
    if running!=release['baselineJarSha256']:raise RuntimeError('Running JAR changed since candidate preparation')
    baseline=release.get('live') or {}
    if baseline.get('imageId')!=previous['Image'] or baseline.get('containerId')!=previous['Id']:
        raise RuntimeError('Daily deployment identity changed since candidate preparation')
    if target['Config']['Entrypoint']!=previous['Config']['Entrypoint']:
        raise RuntimeError('Candidate entrypoint differs')
    helpers.require_standard_deployment(previous);single_writer(previous)
    before=helpers.snapshot()
    if before['mode']!='ACTIVE' or before['namespaces']!='guardian,media':
        raise RuntimeError('Daily SQL business storage must remain initialized and ACTIVE')
    authorization=authorization_snapshot();validate_plan_state(plan,authorization)
    return release,previous,target,before,authorization,plan,sql


def deploy(release_dir,qa_dir,plan_dir,apply=False):
    release_dir,qa_dir,plan_dir=map(lambda p:Path(p).resolve(),(release_dir,qa_dir,plan_dir))
    release,previous,target,before,auth_before,plan,sql=preflight(release_dir,qa_dir,plan_dir)
    if not apply:
        return dict(status='preflight-passed-no-changes',applyRequired=True,imageId=target['Id'],jarSha256=release['jarSha256'])
    stamp=dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ').lower()
    directory=qa_dir/('station-deployment-'+stamp)
    ignored=subprocess.run(['git','check-ignore','-q',str(directory/'deployment.private.json')],cwd=ROOT,capture_output=True)
    if ignored.returncode:raise RuntimeError('Private backup directory is not ignored by Git')
    directory.mkdir()
    retained='melhat-before-station-isolation-'+stamp;failed='melhat-failed-station-isolation-'+stamp
    record=dict(startedAt=helpers.now(),status='preparing',oldImageId=previous['Image'],imageId=target['Id'],
                jarSha256=release['jarSha256'],baselineJarSha256=release['baselineJarSha256'],retainedContainer=retained,
                roleRepairOperationId=plan['operationId'],roleRepairAttempted=False,roleRepairCommitted=False,
                automaticPermissionWidening=False,databaseRestored=False,applicationCredentialsUsed=False,
                before=before,backupDirectory=str(directory))
    helpers.write_json(directory/'deployment.private.json',previous)
    helpers.write_json(directory/'receipt.json',record)
    helpers.write_json(directory/'authorization-before.json',auth_before)
    (directory/'reviewed-apply.sql').write_bytes(sql)
    try:
        helpers.docker('stop','--time','30',helpers.LIVE)
        if helpers.inspect(helpers.LIVE)['State']['Running']:raise RuntimeError('Daily writer did not stop')
        stopped=helpers.snapshot();auth_stopped=authorization_snapshot()
        validate_plan_state(plan,auth_stopped)
        if auth_stopped!=auth_before:raise RuntimeError('Account/role state changed during quiescence; re-audit')
        helpers.write_json(directory/'stopped-state.json',stopped)
        with (directory/'database.sql').open('wb') as output:
            helpers.docker('exec',helpers.MYSQL,'sh','-c',
                'exec mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --single-transaction --skip-lock-tables --hex-blob --default-character-set=utf8mb4 "$1"',
                'station-isolation-backup',helpers.DATABASE,output=output,timeout=600)
        if not (directory/'database.sql').stat().st_size:raise RuntimeError('Empty SQL backup')
        with (directory/'backend-data.tar').open('wb') as output:
            helpers.docker('cp',helpers.LIVE+':/data','-',output=output,timeout=600)
        backups=[]
        for mount in previous.get('Mounts',[]):
            if mount['Destination'] not in helpers.READ_ONLY_CONFIG_MOUNTS:continue
            archive=directory/('readonly-config-'+str(len(backups))+'.private.tar')
            with archive.open('wb') as output:helpers.docker('cp',helpers.LIVE+':'+mount['Destination'],'-',output=output)
            backups.append(dict(destination=mount['Destination'],archive=archive.name,sha256=digest(archive)))
        record.update(status='backed-up',stopped=stopped,databaseSha256=digest(directory/'database.sql'),
                      backendDataSha256=digest(directory/'backend-data.tar'),readOnlyConfigBackups=backups,
                      roleRepairAttempted=True,applySqlSha256=hashlib.sha256(sql).hexdigest())
        helpers.write_json(directory/'receipt.json',record)
        sql_apply(sql)
        auth_repaired=authorization_snapshot();verify_authorization(auth_stopped,auth_repaired,plan)
        record.update(status='role-repair-committed',roleRepairCommitted=True)
        helpers.write_json(directory/'authorization-repaired.json',auth_repaired)
        helpers.write_json(directory/'receipt.json',record)
        helpers.docker('rename',helpers.LIVE,retained)
        helpers.docker(*helpers.recreate_args(previous,target['Id']))
        protected=helpers.anonymous_health();retired=retired_checks()
        current=helpers.inspect(helpers.LIVE)
        if sorted(current['Config'].get('Env',[]))!=sorted(previous['Config'].get('Env',[])):
            raise RuntimeError('Opaque environment changed')
        running=helpers.docker('exec',helpers.LIVE,'sha256sum','/app/fdc-admin.jar').decode().split()[0]
        if running!=release['jarSha256']:raise RuntimeError('Running candidate JAR differs from QA')
        deadline=time.monotonic()+90
        while helpers.read_sql('SELECT COUNT(*) FROM wearable_device_report WHERE processed_at IS NULL AND sequence<='+str(int(stopped['reportWatermark'])))!='0':
            if time.monotonic()>=deadline:raise RuntimeError('Reports through the stopped watermark did not replay')
            time.sleep(1)
        after=helpers.snapshot();helpers.verify_preservation(stopped,after)
        auth_after=authorization_snapshot();verify_authorization(auth_stopped,auth_after,plan)
        helpers.write_json(directory/'authorization-after.json',auth_after)
        record.update(status='deployed',completedAt=helpers.now(),after=after,currentContainerId=current['Id'],
                      anonymousProtectedRequests=protected,retiredEndpoints=retired,
                      unchangedNonTargetRoles=True,unchangedAccounts=True,replayedThrough=stopped['reportWatermark'])
        release.update(state='deployed',newImageId=target['Id'],newContainerId=current['Id'],
                       dailyContainerUnchanged=False,databaseWritesPerformed=True,roleScopeRepairApplied=True,
                       containerPatchReceipt=str(directory/'receipt.json'))
        helpers.write_json(release_dir/'release.json',release)
    except Exception as error:
        # SQL is intentionally never restored or widened, even if candidate startup fails.
        helpers.recover_after_failure(previous,retained,failed,directory,record,error)
        try:
            recovered=authorization_snapshot()
            helpers.write_json(directory/'authorization-after-recovery.json',recovered)
            verify_authorization(auth_before,recovered,plan)
            record['roleRepairRetainedAfterRecovery']=True
        except Exception:
            record['roleRepairRetainedAfterRecovery']='inspect saved authorization evidence'
        helpers.write_json(directory/'receipt.json',record)
        raise RuntimeError('Rollout failed; compatible predecessor recovery attempted, no automatic permission widening. See deployment receipt.') from None
    helpers.write_json(directory/'receipt.json',record)
    return dict(status=record['status'],receipt=str(directory/'receipt.json'),imageId=target['Id'],
                roleRepairCommitted=True,unchangedNonTargetRoles=True,unchangedAccounts=True)


class DeploymentTests(unittest.TestCase):
    def evidence(self):
        release=dict(unchangedNonTaskEntriesVerified=True,jarSha256='hash',publicProtectedCompatibilityWarnings=[])
        smoke=dict(passed=True,dailyContainerUnchanged=True,jarSha256='hash',imageId='image',loginAttempted=False)
        http=dict(passed=True,dailyContainerUnchanged=True,jarSha256='hash',imageId='image',productionWrites=False)
        return release,smoke,http

    def test_evidence_requires_same_image_and_no_live_writes(self):
        data=self.evidence();validate_evidence(*data)
        data[2]['imageId']='other'
        with self.assertRaises(ValueError):validate_evidence(*data)
        data=self.evidence();data[2]['productionWrites']=True
        with self.assertRaises(ValueError):validate_evidence(*data)

    def test_default_is_read_only_preflight(self):
        values=({}, {}, {'Id':'image'}, {}, {}, {}, b'')
        values[0]['jarSha256']='hash'
        with mock_patch(__name__+'.preflight',return_value=values),mock_patch.object(helpers,'docker') as docker:
            result=deploy(BUILD/'release',BUILD/'qa',ROOT/'output/plan')
            self.assertTrue(result['applyRequired']);docker.assert_not_called()

    def test_accounts_and_other_roles_must_not_change(self):
        before=dict(revision=10,accounts=[dict(id='a',version=1,bodyHash='account')],roles=[
            dict(id='mobile-user',version=1,bodyHash='old',stableHash='stable',grants=[dict(siteIds=['site-1','site-2'],operations=['self:read'])]),
            dict(id='audit',bodyHash='keep')])
        after=json.loads(json.dumps(before));after['revision']=11
        after['roles'][0].update(version=2,bodyHash='new');after['roles'][0]['grants'][0]['siteIds']=['site-1']
        verify_authorization(before,after,{})
        after['roles'][1]['bodyHash']='changed'
        with self.assertRaises(RuntimeError):verify_authorization(before,after,{})

    def test_sql_cas_failure_is_not_success(self):
        with mock_patch.object(helpers,'docker',return_value=b'CAS_CONFLICT_NO_CHANGES\n'):
            with self.assertRaises(RuntimeError):sql_apply(b'reviewed')

    def test_retired_endpoint_requires_410(self):
        with mock_patch.object(helpers,'docker',return_value=b'401'):
            with self.assertRaises(RuntimeError):retired_checks()

    def test_stale_plan_is_rejected_before_apply(self):
        plan=dict(expectedSnapshot=dict(meta=[dict(revision=10)],roles=[dict(id='r',bodyHash='a')]))
        with self.assertRaises(ValueError):
            validate_plan_state(plan,dict(revision=11,roles=[dict(id='r',bodyHash='a')]))
        with self.assertRaises(ValueError):
            validate_plan_state(plan,dict(revision=10,roles=[dict(id='r',bodyHash='b')]))

    def test_altered_sql_is_rejected_even_if_plan_is_valid(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory=Path(temporary)/'plan'
            planner.prepare(planner.PlanTests().fixture(),directory)
            verify_plan(directory)
            with (directory/'apply.sql').open('a',encoding='utf-8') as output:
                output.write('\nUPDATE wearable_account SET enabled=0;\n')
            with self.assertRaises(ValueError):verify_plan(directory)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--release-directory',type=Path)
    parser.add_argument('--qa-directory',type=Path)
    parser.add_argument('--plan-directory',type=Path,default=ROOT/'output/station-isolation-20261104-current/mobile-role-repair-plan')
    parser.add_argument('--docker',default=os.environ.get('MELHAT_DOCKER_CLI','docker'))
    parser.add_argument('--apply',action='store_true')
    parser.add_argument('--self-test',action='store_true')
    args=parser.parse_args()
    if args.self_test:
        result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(DeploymentTests))
        raise SystemExit(0 if result.wasSuccessful() else 1)
    if not args.release_directory or not args.qa_directory:parser.error('release and QA directories are required')
    os.environ['MELHAT_DOCKER_CLI']=args.docker
    print(json.dumps(deploy(args.release_directory,args.qa_directory,args.plan_directory,args.apply),ensure_ascii=False))


if __name__=='__main__':
    try:main()
    except (RuntimeError,ValueError,OSError) as error:
        print(str(error),file=sys.stderr);raise SystemExit(1)
