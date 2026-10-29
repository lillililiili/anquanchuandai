"""Explicit, guarded database backup/standby-restore/reconciliation commands.

No routing change or automatic production promotion is performed. The restore target
must belong to the isolated compose project, have no business tables and no running
backend in that project. Passwords remain inside their existing containers.
"""
import argparse,hashlib,json,os,re,subprocess,sys
from pathlib import Path

PROJECTS={'staging':'fuda-wearables-staging','production':'fuda-wearables-production'}
DATABASE='new-helmet'

def run(args,body=None):
    result=subprocess.run(args,input=body,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    if result.returncode:raise RuntimeError('Container/database operation failed; inspect private service logs.')
    return result.stdout

def identity(container):
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*',container):raise ValueError('Invalid container name')
    return json.loads(run(['docker','inspect',container]))[0]

def mysql(container,sql):
    identity(container)
    return run(['docker','exec','-i',container,'sh','-c',
        'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot --batch --skip-column-names --default-character-set=utf8mb4 new-helmet'],sql.encode())

def target_guard(container,role='staging'):
    if role not in PROJECTS:raise ValueError('Unknown deployment role')
    project=PROJECTS[role]
    info=identity(container);labels=info['Config'].get('Labels') or {}
    if labels.get('com.docker.compose.project')!=project or labels.get('com.docker.compose.service')!='mysql' or labels.get('com.wearables.deployment-role')!=role:
        raise ValueError('Restore target must match the explicitly selected isolated project and role')
    active=run(['docker','ps','-q','--filter',f'label=com.docker.compose.project={project}','--filter','label=com.docker.compose.service=backend']).strip()
    if active:raise ValueError('Stop the standby backend before restore')
    count=int(mysql(container,"SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='new-helmet';").strip())
    if count:raise ValueError('Restore target is not empty; this tool never overwrites a populated database')

def inventory(container):
    names=mysql(container,"SELECT table_name FROM information_schema.tables WHERE table_schema='new-helmet' AND table_type='BASE TABLE' ORDER BY table_name;").decode().splitlines()
    counts={}
    for name in names:
        if not re.fullmatch(r'[A-Za-z0-9_]+',name):raise ValueError('Unexpected table identifier')
        counts[name]=int(mysql(container,f'SELECT COUNT(*) FROM `{name}`;').strip())
    result={'container':container,'counts':counts}
    if 'wearable_device_report' in counts:
        values=mysql(container,'SELECT COALESCE(MAX(sequence),0),COALESCE(SUM(processed_at IS NULL),0) FROM wearable_device_report;').decode().strip().split('\t')
        result['reportWatermark']=int(values[0]);result['pendingReports']=int(values[1])
    return result

def backup(container,destination):
    identity(container);destination=Path(destination)
    if destination.exists() or destination.with_suffix(destination.suffix+'.sha256').exists():raise ValueError('Backup destination or checksum already exists')
    # No command interpolates a password or arbitrary database name.
    data=run(['docker','exec',container,'sh','-c',
        'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysqldump -uroot --single-transaction --routines --triggers --hex-blob --set-gtid-purged=OFF --no-tablespaces --default-character-set=utf8mb4 new-helmet'])
    if not data.strip():raise ValueError('Empty backup')
    destination.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
    with os.fdopen(os.open(destination,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600),'wb') as out:out.write(data)
    digest=hashlib.sha256(data).hexdigest()
    with os.fdopen(os.open(destination.with_suffix(destination.suffix+'.sha256'),os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600),'w',encoding='ascii') as out:out.write(digest+'\n')
    return {'bytes':len(data),'sha256':digest,'containsPrivateData':True}

def restore(container,source,expected,role='staging'):
    target_guard(container,role);data=Path(source).read_bytes()
    if hashlib.sha256(data).hexdigest()!=expected.lower():raise ValueError('Backup hash mismatch')
    mysql(container,data.decode('utf-8'))
    return inventory(container)

def main():
    p=argparse.ArgumentParser();sub=p.add_subparsers(dest='command');sub.required=True
    a=sub.add_parser('inventory');a.add_argument('--container',required=True)
    a=sub.add_parser('backup');a.add_argument('--container',required=True);a.add_argument('--output',required=True)
    a=sub.add_parser('restore-standby');a.add_argument('--container',required=True);a.add_argument('--dump',required=True);a.add_argument('--sha256',required=True);a.add_argument('--target-role',choices=tuple(PROJECTS),required=True)
    a=sub.add_parser('compare');a.add_argument('--before',required=True);a.add_argument('--after',required=True)
    args=p.parse_args()
    if args.command=='inventory':result=inventory(args.container)
    elif args.command=='backup':result=backup(args.container,args.output)
    elif args.command=='restore-standby':result=restore(args.container,args.dump,args.sha256,args.target_role)
    else:
        before=json.loads(Path(args.before).read_text(encoding='utf-8-sig'));after=json.loads(Path(args.after).read_text(encoding='utf-8-sig'))
        changed={k:{'before':v,'after':after['counts'].get(k)} for k,v in before['counts'].items() if after['counts'].get(k)!=v}
        result={'sameExistingTableCounts':not changed,'differences':changed,
          'sameReportWatermark':before.get('reportWatermark')==after.get('reportWatermark'),
          'samePendingReports':before.get('pendingReports')==after.get('pendingReports')}
        print(json.dumps(result,ensure_ascii=False,indent=2));return 0 if not changed and result['sameReportWatermark'] and result['samePendingReports'] else 2
    print(json.dumps(result,ensure_ascii=False,indent=2));return 0

if __name__=='__main__':
    try:sys.exit(main())
    except (ValueError,RuntimeError,OSError) as error:print(str(error),file=sys.stderr);sys.exit(2)
