"""Make an allowlisted JAR patch from a read-only copy of the running backend.

No container is created, built, stopped, restarted, or changed. No SQL is executed.
Only listed top-level classes and their inner classes plus admin-seed.json may change.
The running JAR, not the full Maven output, supplies every other archive entry.
"""
import argparse
import copy
import datetime as dt
import difflib
import hashlib
import io
import json
from pathlib import Path
import re
import shutil
import subprocess
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BACKEND = ROOT / '后端代码/melhat_server-dev'
ALLOW = {
    'ruoyi-admin': ['com/ruoyi/guardian/' + name for name in (
        'AdminAccessService','AdminAssignmentService','AdminDeviceService','AdminMaintenanceService',
        'AdminMasterService','AdminQueryService','GuardianAccess','GuardianMasterProjection','GuardianIngest','WearableModel','LegacyCallbackAccess')]
        + ['com/ruoyi/web/controller/business/ExternalController'],
    'ruoyi-framework': ['com/ruoyi/framework/config/SecurityConfig',
                        'com/ruoyi/framework/security/filter/LegacyEndpointBoundaryFilter'],
    'ruoyi-system': ['com/ruoyi/system/websocket/WebSocketSever'],
}
RESOURCES = ['admin-seed.json']


def sha(data): return hashlib.sha256(data).hexdigest()


def docker_read(docker, *args):
    if not args or args[0] not in ('inspect','cp','exec'):
        raise ValueError('Only read-only Docker operations are supported')
    if args[0]=='exec' and args[1:] != ('melhat-backend','sha256sum','/app/fdc-admin.jar'):
        raise ValueError('Only the running JAR digest can be executed')
    try:
        result=subprocess.run([docker,*args],capture_output=True,timeout=60)
    except (OSError,subprocess.TimeoutExpired):
        raise RuntimeError('Read-only Docker operation unavailable') from None
    if result.returncode:raise RuntimeError('Read-only Docker operation failed: '+args[0])
    return result.stdout


def allowed(module,name):
    return any(name==base+'.class' or name.startswith(base+'$') and name.endswith('.class') for base in ALLOW[module])


def entries(data):
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        names=z.namelist()
        if len(names)!=len(set(names)):raise ValueError('Duplicate archive entries are not supported')
        return {name:z.read(name) for name in names}


def rewrite(data, updates, removals):
    result=io.BytesIO()
    with zipfile.ZipFile(io.BytesIO(data)) as source,zipfile.ZipFile(result,'w') as target:
        original=set(source.namelist())
        if len(original)!=len(source.infolist()):raise ValueError('Duplicate archive entry')
        target.comment=source.comment
        for item in source.infolist():
            if item.filename in removals:continue
            target.writestr(copy.copy(item),updates.get(item.filename,source.read(item.filename)))
        for name,value in sorted(updates.items()):
            if name not in original:target.writestr(name,value,compress_type=zipfile.ZIP_DEFLATED)
    return result.getvalue()


def verify_unchanged(before,after,permitted):
    for name in set(before)|set(after):
        if name not in permitted and before.get(name)!=after.get(name):
            raise ValueError('Unlisted archive entry changed: '+name)
    return sum(name not in permitted for name in before)


def changes(before,after):
    return [dict(entry=name,oldSha256=sha(before[name]) if name in before else None,
                 newSha256=sha(after[name]) if name in after else None)
            for name in sorted(set(before)|set(after)) if before.get(name)!=after.get(name)]


def compiled(module):
    target=BACKEND/module/'target/classes'
    result={}
    for base in ALLOW[module]:
        main=target/(base+'.class')
        if not main.is_file():raise ValueError('Missing compiled class: '+str(main))
        source=BACKEND/module/'src/main/java'/(base+'.java')
        if not source.is_file():raise ValueError('Missing source: '+str(source))
        if source.stat().st_mtime>main.stat().st_mtime+2:
            raise ValueError('Source newer than compiled class: '+str(source))
        for path in [main,*sorted(main.parent.glob(main.stem+'$*.class'))]:
            result[path.relative_to(target).as_posix()]=path.read_bytes()
    return result


def disassemble(javap,path):
    result=subprocess.run([javap,'-c','-p','-s',str(path)],capture_output=True,timeout=20)
    if result.returncode:raise RuntimeError('javap could not inspect selected class')
    text=result.stdout.decode('utf-8',errors='replace')
    # Constant pool indexes change when unrelated methods are inserted. Symbol comments remain.
    return re.sub(r'#\d+', '#POOL',text)


def public_members(text):
    result=set()
    lines=text.splitlines()
    for i,line in enumerate(lines):
        if re.match(r'^  (public|protected) ',line):
            signature=re.sub(r' throws .*;', ';',line.strip())
            if i+1<len(lines) and 'descriptor:' in lines[i+1]:
                result.add(signature+' '+lines[i+1].strip())
    return result


def linkage_members(text):
    """Package-visible members can be referenced by unpatched sibling classes too."""
    result=set()
    lines=text.splitlines()
    for i,line in enumerate(lines):
        if line.startswith('  ') and not line.startswith('    ') and not line.strip().startswith('private '):
            if i+1<len(lines) and 'descriptor:' in lines[i+1]:
                result.add(re.sub(r' throws .*;', ';',line.strip())+' '+lines[i+1].strip())
    return result


def verify_methods(directory,javap,module,before,after):
    evidence=[]
    for name in sorted(set(before)|set(after)):
        if not allowed(module,name) or before.get(name)==after.get(name):continue
        item=dict(module=module,entry=name,status='added' if name not in before else 'removed' if name not in after else 'changed')
        if name in before and name in after:
            old=directory/'bytecode'/module/'before'/name
            new=directory/'bytecode'/module/'after'/name
            old.parent.mkdir(parents=True,exist_ok=True);new.parent.mkdir(parents=True,exist_ok=True)
            old.write_bytes(before[name]);new.write_bytes(after[name])
            old_text,new_text=disassemble(javap,old),disassemble(javap,new)
            removed=sorted(public_members(old_text)-public_members(new_text))
            item['removedPublicProtectedMembers']=removed
            item['removedNonPrivateMembers']=sorted(linkage_members(old_text)-linkage_members(new_text))
            item['bytecodeSemanticallyUnchangedAfterPoolNormalization']=old_text==new_text
            diff=directory/'bytecode-diffs'/module/(name[:-6]+'.diff')
            diff.parent.mkdir(parents=True,exist_ok=True)
            diff.write_text(''.join(difflib.unified_diff(old_text.splitlines(True),new_text.splitlines(True),fromfile='live/'+name,tofile='candidate/'+name)),encoding='utf-8')
            item['diff']=str(diff.relative_to(directory))
        evidence.append(item)
    return evidence


def build(directory,docker,javap,baseline=None):
    directory=directory.resolve()
    if not any(directory.is_relative_to(parent) and directory!=parent for parent in (ROOT/'output',BACKEND/'build')):
        raise ValueError('Output must be below workspace output or backend/build')
    if directory.exists():raise ValueError('Output already exists; no files overwritten')
    if not Path(javap).is_file():raise ValueError('Explicit javap executable required for compatibility evidence')
    directory.mkdir(parents=True)
    live=None
    baseline_path=directory/'baseline-fdc-admin.jar'
    if baseline:
        shutil.copyfile(baseline,baseline_path)
    else:
        # Explicitly restrict Docker inspect output to non-secret identity/status fields.
        raw=docker_read(docker,'inspect','--format','{{json .Id}} {{json .Image}} {{json .State.Running}}','melhat-backend').decode().strip()
        parts=raw.split(' ')
        if len(parts)!=3 or parts[2]!='true':raise ValueError('Daily backend must be running')
        live=dict(containerId=json.loads(parts[0]),imageId=json.loads(parts[1]))
        before_digest=docker_read(docker,'exec','melhat-backend','sha256sum','/app/fdc-admin.jar').decode().split()[0]
        docker_read(docker,'cp','melhat-backend:/app/fdc-admin.jar',str(baseline_path))
        if sha(baseline_path.read_bytes())!=before_digest:raise ValueError('Running JAR changed during read-only copy')
    baseline_bytes=baseline_path.read_bytes()
    outer_before=entries(baseline_bytes)
    outer_updates={};outer_removals=set();nested_manifests=[];method_evidence=[];sources=[]
    for module in ALLOW:
        replacement=compiled(module)
        for base in ALLOW[module]:
            path=BACKEND/module/'src/main/java'/(base+'.java')
            sources.append(dict(path=str(path.relative_to(ROOT)),sha256=sha(path.read_bytes())))
        if module=='ruoyi-admin':
            before={name[len('BOOT-INF/classes/'):]:value for name,value in outer_before.items() if name.startswith('BOOT-INF/classes/')}
            removed={name for name in before if allowed(module,name) and name not in replacement}
            outer_updates.update({'BOOT-INF/classes/'+name:value for name,value in replacement.items()})
            outer_removals.update('BOOT-INF/classes/'+name for name in removed)
            after=dict(before);after.update(replacement)
            for name in removed:after.pop(name)
        else:
            lib='BOOT-INF/lib/'+module+'-3.8.5.jar'
            if lib not in outer_before:raise ValueError('Expected nested module missing: '+lib)
            before=entries(outer_before[lib])
            if any(re.match(r'META-INF/[^/]+\.(SF|RSA|DSA|EC)$',name,re.I) for name in before):
                raise ValueError('Refusing to alter signed module: '+lib)
            removed={name for name in before if allowed(module,name) and name not in replacement}
            changed_jar=rewrite(outer_before[lib],replacement,removed)
            after=entries(changed_jar)
            count=verify_unchanged(before,after,set(replacement)|removed)
            nested_manifests.append(dict(entry=lib,oldSha256=sha(outer_before[lib]),newSha256=sha(changed_jar),
                                         unchangedEntriesVerified=count,changes=changes(before,after)))
            outer_updates[lib]=changed_jar
        method_evidence.extend(verify_methods(directory,javap,module,before,after))
    for resource in RESOURCES:
        source=BACKEND/'ruoyi-admin/src/main/resources'/resource
        built=BACKEND/'ruoyi-admin/target/classes'/resource
        if source.read_bytes()!=built.read_bytes():raise ValueError('Compiled resource differs from current source: '+resource)
        sources.append(dict(path=str(source.relative_to(ROOT)),sha256=sha(source.read_bytes())))
        outer_updates['BOOT-INF/classes/'+resource]=built.read_bytes()
    candidate=rewrite(baseline_bytes,outer_updates,outer_removals)
    outer_after=entries(candidate)
    verified=verify_unchanged(outer_before,outer_after,set(outer_updates)|outer_removals)
    (directory/'fdc-admin.jar').write_bytes(candidate)
    previous=BACKEND/'build/dispatch-groups-20261104t024402z/release.json'
    previous_release=json.loads(previous.read_text(encoding='utf-8')) if previous.exists() else {}
    incompatible=[item for item in method_evidence if item.get('removedNonPrivateMembers') or item['status']=='removed']
    manifest=dict(state='candidate-only-not-deployed',createdAtUtc=dt.datetime.now(dt.timezone.utc).isoformat(),
                  baselineJarSha256=sha(baseline_bytes),jarSha256=sha(candidate),live=live,
                  baselineMatchesPriorDispatchRelease=sha(baseline_bytes)==previous_release.get('jarSha256'),
                  unchangedNonTaskEntriesVerified=True,unchangedOuterEntriesVerified=verified,
                  allowlistedTopLevelClasses=ALLOW,allowedResources=RESOURCES,
                  outerChanges=changes(outer_before,outer_after),nestedModules=nested_manifests,
                  selectedSourceHashes=sources,bytecodeEvidence=method_evidence,
                  publicProtectedCompatibilityWarnings=incompatible,
                  compatibilityLimit='Selected class families include all current source changes. Review bytecode diffs; unchanged entries prove only nonselected content preservation, not functional compatibility.',
                  containerBuildPerformed=False,dailyContainerUnchanged=True,databaseWritesPerformed=False)
    (directory/'release.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    if live:
        current=docker_read(docker,'exec','melhat-backend','sha256sum','/app/fdc-admin.jar').decode().split()[0]
        if current!=manifest['baselineJarSha256']:raise ValueError('Live JAR changed; candidate must be rebased')
    return dict(directory=str(directory),baselineJarSha256=manifest['baselineJarSha256'],jarSha256=manifest['jarSha256'],
                nonTaskEntriesVerified=verified,outerChanges=len(manifest['outerChanges']),
                compatibilityWarnings=len(incompatible),dailyContainerUnchanged=True)


class CandidateTests(unittest.TestCase):
    def archive(self,mapping):
        data=io.BytesIO()
        with zipfile.ZipFile(data,'w') as z:
            for key,value in mapping.items():z.writestr(key,value)
        return data.getvalue()

    def test_class_family_allowlist_is_exact(self):
        self.assertTrue(allowed('ruoyi-admin','com/ruoyi/guardian/GuardianAccess$Context.class'))
        self.assertFalse(allowed('ruoyi-admin','com/ruoyi/guardian/GuardianAccessOther.class'))
        self.assertFalse(allowed('ruoyi-admin','com/ruoyi/guardian/GuardianStore.class'))

    def test_rewrite_preserves_unlisted_bytes_and_metadata(self):
        original=self.archive({'keep':b'original','change':b'before','obsolete':b'old'})
        modified=rewrite(original,{'change':b'after','new':b'new'}, {'obsolete'})
        self.assertEqual(entries(modified)['keep'],b'original')
        self.assertEqual(verify_unchanged(entries(original),entries(modified),{'change','new','obsolete'}),1)

    def test_unauthorized_change_fails(self):
        with self.assertRaises(ValueError):verify_unchanged({'keep':b'a'},{'keep':b'b'},set())

    def test_nested_jar_preservation(self):
        original=self.archive({'one.class':b'a','two.class':b'b'})
        nested=rewrite(original,{'one.class':b'new'},set())
        outer=self.archive({'BOOT-INF/lib/module.jar':original,'BOOT-INF/classes/Keep.class':b'c'})
        changed=rewrite(outer,{'BOOT-INF/lib/module.jar':nested},set())
        self.assertEqual(entries(entries(changed)['BOOT-INF/lib/module.jar'])['two.class'],b'b')
        verify_unchanged(entries(outer),entries(changed),{'BOOT-INF/lib/module.jar'})

    def test_public_signature_collection(self):
        old='  public boolean accept(java.lang.String);\n    descriptor: (Ljava/lang/String;)Z\n'
        self.assertTrue(public_members(old))
        self.assertEqual(public_members(old)-public_members(old),set())

    def test_package_visible_linkage_is_checked(self):
        old='  static boolean accept(java.lang.String);\n    descriptor: (Ljava/lang/String;)Z\n'
        self.assertTrue(linkage_members(old))
        self.assertFalse(public_members(old))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory',type=Path,default=BACKEND/'build/station-isolation-20261104')
    parser.add_argument('--docker',default='docker')
    parser.add_argument('--javap',default=str(Path.home()/'.jdks/temurin-17/bin/javap.exe'))
    parser.add_argument('--baseline',type=Path,help='Explicit already-copied baseline; otherwise copy running JAR read-only')
    parser.add_argument('--self-test',action='store_true')
    args=parser.parse_args()
    if args.self_test:
        result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(CandidateTests))
        raise SystemExit(0 if result.wasSuccessful() else 1)
    print(json.dumps(build(args.directory,args.docker,args.javap,args.baseline),ensure_ascii=False))


if __name__=='__main__':main()
