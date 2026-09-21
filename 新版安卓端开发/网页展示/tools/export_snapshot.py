"""Read-only business snapshot for an entirely offline presentation."""
from pathlib import Path
import subprocess,json,re,datetime
ROOT=Path(__file__).resolve().parents[1]
def query(sql):
    assert not re.search(r'\b(INSERT|UPDATE|DELETE|DROP|ALTER|REPLACE|TRUNCATE)\b',sql,re.I)
    p=subprocess.run(['docker','exec','-i','melhat-mysql','sh','-c','MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot --default-character-set=utf8mb4 --batch --raw --skip-column-names -D "$MYSQL_DATABASE"'],input='SET SESSION TRANSACTION READ ONLY; START TRANSACTION READ ONLY;\n'+sql+'\nCOMMIT;',text=True,encoding='utf-8',capture_output=True,check=True)
    return [json.loads(x) for x in p.stdout.splitlines() if x.strip()]
def camel(k):
    p=k.split('_');return p[0]+''.join(x.title() for x in p[1:])
def table(t):
    cols=query("SELECT JSON_QUOTE(column_name) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='"+t+"' ORDER BY ordinal_position;")
    fields=','.join("'"+camel(c)+"',`"+c+'`' for c in cols)
    found=query('SELECT JSON_OBJECT('+fields+') FROM `'+t+'`;')
    for row in found:
        for k,v in list(row.items()):
            if v is not None and (k=='id' or k.endswith('Id')):row[k]=str(v)
            if k in ['demo','enabled','ticketRequired','enterEnabled','leaveEnabled']:row[k]=bool(v)
            if k in ['capabilities','polygonJson','payloadJson'] and isinstance(v,str):
                try:row[k]=json.loads(v)
                except ValueError:pass
    return found
names={'sites':'wear_site','people':'wear_person','peopleSites':'wear_person_site','devices':'wear_device','models':'wear_product_model','assignments':'wear_assignment','teams':'wear_team','spaces':'wear_space','tasks':'wear_work_task','members':'wear_work_task_member','requirements':'wear_work_task_requirement','events':'wear_safety_event','eventActions':'wear_event_action','fences':'wear_geo_fence','handovers':'wear_duty_handover','calls':'wear_call_session'}
data={k:table(t) for k,t in names.items()}
data['samples']=table('wear_device_sample')
keys=subprocess.run(['docker','exec','melhat-redis','redis-cli','--scan','--pattern','wear:map:osm:*'],text=True,capture_output=True,check=True).stdout.splitlines()
data['mapTiles']={}
for key in keys:
    value=subprocess.run(['docker','exec','melhat-redis','redis-cli','--raw','GET',key],text=True,capture_output=True,check=True).stdout.strip()
    try:value=json.loads(value)
    except ValueError:pass
    if isinstance(value,str):data['mapTiles'][key.removeprefix('wear:map:osm:')]=value
users=query("SELECT JSON_OBJECT('userId',CAST(user_id AS CHAR),'userName',user_name,'nickName',nick_name,'sipId',sip_id) FROM sys_user WHERE del_flag='0';")
user={u['userId']:u for u in users};people={p['id']:p for p in data['people']};model={m['id']:m for m in data['models']};team={t['id']:t for t in data['teams']};space={s['id']:s for s in data['spaces']}
for handover in data['handovers']:
    for side in ['from','to']:
        u=user.get(handover.get(side+'UserId'),{})
        handover[side+'UserName']=u.get('nickName') or u.get('userName') or handover.get(side+'UserId')
    if isinstance(handover.get('payloadJson'),dict):handover['payloadJson']=json.dumps(handover['payloadJson'],ensure_ascii=False,separators=(',',':'))
now=datetime.datetime.now()
for p in data['people']:
    p['teamName']=team.get(p.get('teamId'),{}).get('name','')
    p['siteIds']=[r['siteId'] for r in data['peopleSites'] if r['personId']==p['id'] and r['status']=='0']
    p['selectable']=p.get('status')=='0' and bool(p['siteIds']) and (not p.get('validTo') or p['validTo']>=now.strftime('%Y-%m-%d'))
for d in data['devices']:
    m=model.get(d.get('modelId'),{});d.update(typeCode=m.get('typeCode'),modelName=m.get('name'),capabilities=m.get('capabilities',{}),demo=True)
    a=next((a for a in data['assignments'] if a['deviceId']==d['id'] and not a.get('returnedAt')),None)
    d['personId']=a['personId'] if a else None;d['personName']=people.get(d['personId'],{}).get('name','');d['assignmentId']=a['id'] if a else None
    fresh=False
    if d.get('lastReportedAt'):
        try:fresh=(now-datetime.datetime.fromisoformat(d['lastReportedAt'])).total_seconds()<180
        except ValueError:pass
    d['connectionQuality']='ok' if fresh else ('stale' if d.get('lastReportedAt') else 'unknown')
devices={d['id']:d for d in data['devices']}
for a in data['assignments']:
    d=devices.get(a['deviceId'],{});p=people.get(a['personId'],{})
    for k in ['sn','typeCode','modelName','online','connectionQuality','capabilities','battery']:a[k]=d.get(k)
    a.update(personName=p.get('name'),personCode=p.get('personCode'),demo=True,assignedAt=a.get('issuedAt'))
for d in data['devices']:d['currentAssignment']=next((a for a in data['assignments'] if a['deviceId']==d['id'] and a.get('returnedAt') is None),None)
data['tasks'].sort(key=lambda t:int(t['id']),reverse=True)
for t in data['tasks']:
    t['members']=[dict(r,name=people.get(r['personId'],{}).get('name'),personName=people.get(r['personId'],{}).get('name'),personCode=people.get(r['personId'],{}).get('personCode')) for r in data['members'] if r['taskId']==t['id']]
    t['requirements']=[r for r in data['requirements'] if r['taskId']==t['id']]
    t['spaceName']=space.get(t.get('spaceId'),{}).get('name','');t['guardianName']=people.get(t.get('guardianPersonId'),{}).get('name','');t['ownerName']=user.get(t.get('ownerUserId'),{}).get('nickName','')
    for k in ['plannedStart','plannedEnd','actualStart','actualEnd']:t[k+'At']=t.get(k)
for e in data['events']:e['type']=e.pop('eventType');e['demo']=True;e['deviceType']=devices.get(e.get('deviceId'),{}).get('typeCode','')
for f in data['fences']:f['polygon']=f.get('polygonJson')
data['events'].sort(key=lambda e:e.get('occurredAt',''),reverse=True)
data['people'].sort(key=lambda p:(p.get('personCode')!='P-001',p.get('personCode','')))
core=next(p for p in data['people'] if p.get('personCode')=='P-001')
data['identity']={'status':'0','userId':core['accountUserId'],'personId':core['id'],'nickName':core['name'],'name':core['name'],'userName':'静态展示','roles':['wear_duty','wear_team_lead','wear_reviewer'],'permissions':['*:*:*','wear:call:start','wear:command:tts'],'authorizedSites':data['sites']}
data['identity'].update({k:user.get(core['accountUserId'],{}).get(k) for k in ['userName','sipId']})
data['operators']=[dict(user[u],name=user[u]['nickName']) for u in user if any(t.get('ownerUserId')==u for t in data['tasks'])]
data['capturedAt']=now.astimezone().isoformat();data['dataMode']='只读数据库快照；网页操作仅在浏览器内存中演示'
out=ROOT/'展示源码/assets/preview';out.mkdir(parents=True,exist_ok=True)
(out/'snapshot.json').write_text(json.dumps(data,ensure_ascii=False,separators=(',',':')),'utf-8')
summary={k:len(v) for k,v in data.items() if isinstance(v,list)}
(ROOT/'同步验收/20260921/数据快照说明.json').write_text(json.dumps({'capturedAt':data['capturedAt'],'mode':data['dataMode'],'counts':summary,'exportedCredentials':False},ensure_ascii=False,indent=2),'utf-8')
print(json.dumps(summary,ensure_ascii=False))
