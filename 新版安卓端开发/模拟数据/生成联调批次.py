"""Generate deterministic, labelled business fixtures; does not execute seed SQL."""
import json, math, secrets, subprocess, sys
from collections import defaultdict
from datetime import datetime, timedelta
from pathlib import Path
from 执行工具 import ROOT, mysql, rows, save

B = sorted(ROOT.glob('执行批次-*'))[-1]
assert not (B/'已提交.json').exists(), 'Committed batch cannot be regenerated'
META = json.loads((B/'备份验证.json').read_text('utf-8'))
SCRATCH = META['scratchDatabase']
NOW = datetime.now().replace(microsecond=0)
DAY = NOW.replace(hour=0,minute=0,second=0)
TAG = 'QA'+META['batch'].split('-')[-1]
DATA = defaultdict(list)
NEXT = {}
SCHEMA = rows("SELECT JSON_OBJECT('table',table_name,'column',column_name,'extra',extra) FROM information_schema.columns WHERE table_schema=DATABASE();", SCRATCH)
AUTO = {r['table']:r['column'] for r in SCHEMA if r['extra']=='auto_increment'}
for t,c in AUTO.items():
    NEXT[t] = int(mysql(f'SELECT COALESCE(MAX(`{c}`),0)+1 FROM `{t}`;',SCRATCH))

def at(days=0,hours=0,minutes=0): return DAY+timedelta(days=days,hours=hours,minutes=minutes)
def stamp(v): return v.strftime('%Y-%m-%d %H:%M:%S') if isinstance(v,datetime) else v
def add(t, **v):
    cols={r['column'] for r in SCHEMA if r['table']==t}
    if t in AUTO:
        v[AUTO[t]]=NEXT[t]; NEXT[t]+=1
    if 'create_by' in cols: v.setdefault('create_by','demo')
    if 'create_time' in cols: v.setdefault('create_time',at(-75))
    assert set(v)<=cols,(t,set(v)-cols)
    DATA[t].append({k:stamp(x) for k,x in v.items()})
    return v.get(AUTO.get(t,'id'))

def password_hash(password):
    java='import java.io.*; import org.springframework.security.crypto.bcrypt.BCrypt; class QaHash { public static void main(String[] a) throws Exception { System.out.print(BCrypt.hashpw(new BufferedReader(new InputStreamReader(System.in)).readLine(), BCrypt.gensalt())); }}'
    p=B/'QaHash.java'; p.write_text(java,'utf-8')
    subprocess.run(['docker','cp',str(p),'melhat-backend:/tmp/QaHash.java'],check=True,capture_output=True)
    return subprocess.run(['docker','exec','-i','melhat-backend','java','--class-path','/root/.m2/repository/org/springframework/security/spring-security-crypto/5.5.8/spring-security-crypto-5.5.8.jar','/tmp/QaHash.java'],input=password+'\n',text=True,capture_output=True,check=True).stdout.strip()

org=add('sys_dept',parent_id=100,ancestors='0,100',dept_name='联调测试组织',dept_code=TAG,order_num=90)
deps=[add('sys_dept',parent_id=org,ancestors=f'0,100,{org}',dept_name=n,dept_code=TAG+'D'+str(i),order_num=i) for i,n in enumerate(['运行部','检修部','安全管理部','外协管理部'])]
teams=[add('wear_team',site_id=s,name=n) for s,n in [(1,'A站运行一班（联调）'),(1,'A站设备检修班（联调）'),(1,'A站外协班（联调）'),(2,'B站风机运维班（联调）')]]
contractors=[add('wear_contractor',name=n) for n in ['齐安设备检修测试队','恒风运维测试队']]
areaA=add('wear_space',site_id=1,space_type='area',name='热电生产区（联调）')
boiler=add('wear_space',site_id=1,parent_id=areaA,space_type='facility',name='1号锅炉')
floorA=add('wear_space',site_id=1,parent_id=boiler,space_type='floor',name='锅炉12米平台')
turbine=add('wear_space',site_id=1,parent_id=areaA,space_type='facility',name='汽机房')
add('wear_space',site_id=1,parent_id=turbine,space_type='floor',name='汽机运转层')
add('wear_space',site_id=1,parent_id=areaA,space_type='facility',name='升压站')
areaB=add('wear_space',site_id=2,space_type='area',name='风电场北区（联调）')
fan=add('wear_space',site_id=2,parent_id=areaB,space_type='facility',name='F01风机')
floorB=add('wear_space',site_id=2,parent_id=fan,space_type='floor',name='塔筒检修平台')
add('wear_space',site_id=2,parent_id=areaB,space_type='facility',name='风电升压站')

names='陈建国 周明 李志远 赵启航 孙立 王海涛 刘文博 张俊峰 马伟 黄磊 杨帆 吴志强 徐成 何军 高鹏 林浩 郭健 罗文 宋涛 郑凯 许晨 邓平 冯源 曹斌 韩松 沈杰 谢安 唐宇 魏东 杜明 田野 余峰 潘毅 袁超 董成 苏宁 蒋华 程远 叶青 蔡林 卢飞 汪海'.split()
# Real role keys already supported by the system; no extra roles or legacy grants.
account_specs=[(0,'qa_chen',205,1),(1,'qa_zhou',205,1),(2,'qa_a_duty',203,1),(3,'qa_zhao',206,1),(4,'qa_sun',206,1),(5,'qa_a_devices',202,1),(6,'qa_a_review',204,1),(7,'qa_cross',206,1),(8,'qa_a_duty2',203,1),(27,'qa_b_duty',203,2),(28,'qa_b_duty2',203,2),(29,'qa_b_devices',202,2),(30,'qa_b_review',204,2),(31,'qa_b_readonly',206,2)]
password='Qa!'+secrets.token_urlsafe(12)
hashed=password_hash(password)
accounts={}; credentials=[]
for i,username,role,site in account_specs:
    uid=add('sys_user',dept_id=deps[2 if role==204 else 0],user_name=username,nick_name=names[i],password=hashed,remark=f'{TAG} 合成联调账号，不含员工私人信息')
    add('sys_user_role',user_id=uid,role_id=role)
    for s in ([1,2] if username=='qa_cross' else [site]): add('wear_site_account',site_id=s,user_id=uid)
    accounts[i]=(uid,username,role)
    credentials.append({'username':username,'password':password,'userId':uid,'person':names[i],'roleId':role,'siteIds':[1,2] if username=='qa_cross' else [site]})
save(B/'测试账号-请勿外传.json',credentials)
P=[]
for i,n in enumerate(names):
    site=1 if i<27 else 2
    team=teams[i%3] if site==1 else teams[3]
    code=f'P-{i+1:03}' if i<5 else f'QA-P{i+1:03}'
    status='1' if i in (25,40) else '0'
    extra='；停用边界样本' if status=='1' else ('；已调离边界样本' if i in (26,41) else ('；有效期已过边界样本' if i==24 else ''))
    pid=add('wear_person',person_code=code,name=n,org_dept_id=deps[i%4],team_id=team,contractor_id=contractors[site-1] if i%5==0 and i>4 else None,account_user_id=accounts.get(i,(None,))[0],status=status,valid_from=at(-90).strftime('%Y-%m-%d'),valid_to=at(-1 if i==24 else 365).strftime('%Y-%m-%d'),remark=TAG+' 合成人员'+extra)
    add('wear_person_site',person_id=pid,site_id=site,status='1' if i in (26,41) else '0')
    if i in (7,21,32,33): add('wear_person_site',person_id=pid,site_id=3-site)
    P.append({'id':pid,'name':n,'code':code,'site':site})

voice=add('wear_product_model',type_code='helmet',model_code='QA-HAT-VOICE',manufacturer_code='MELHAT',name='联调语音安全帽（无视频）',protocol_version='demo-hat-v1',capabilities=json.dumps({'protocolVersion':'demo-hat-v1','attributes':['battery','online','gnss'],'events':['sos','fall'],'actions':['tts','intercom']},separators=(',',':')))
held_people=list(range(20))+list(range(27,36))
H=[]; BELT=[]
for i in range(32):
    person=held_people[i] if i<29 else None
    site=P[person]['site'] if person is not None else (1 if i==29 else 2)
    model=2 if i==4 else (voice if i in (1,6,12,22,27) else 1)
    state='issued' if i<29 else ['maintenance','disabled','scrapped'][i-29]
    sn='RL-H001' if i==0 else f'QA-H{i+1:03}'
    did=add('wear_device',manufacturer_code='MELHAT',sn=sn,model_id=model,site_id=site,asset_status=state,remark=TAG+' 合成装备；非真实硬件')
    H.append({'id':did,'sn':sn,'site':site,'person':person,'model':model})
for i in range(23):
    person=[0,1,2,5,6,7,27,28,29][i] if i<9 else None
    site=P[person]['site'] if person is not None else (1 if i%2==0 else 2)
    state='issued' if i<9 else ('in_stock' if i<18 else ('maintenance' if i<20 else ('disabled' if i<22 else 'scrapped')))
    sn='RL-B001' if i==0 else f'QA-B{i+1:03}'
    did=add('wear_device',manufacturer_code='MELHAT',sn=sn,model_id=3,site_id=site,asset_status=state,remark=TAG+' 合成装备；传感器未知')
    BELT.append({'id':did,'sn':sn,'site':site,'person':person,'model':3})

def assign(d,pi,start,end=None):
    pid=P[pi]['id']
    aid=add('wear_assignment',device_id=d['id'],person_id=pid,site_id=d['site'],issued_at=start,returned_at=end,issued_by='demo',returned_by='demo' if end else None,return_reason=TAG+' 历史归还样本' if end else None,return_kind='return' if end else None,create_time=start,update_time=end,version=2 if end else 1)
    add('wear_asset_audit',action='issue',device_id=d['id'],assignment_id=aid,person_id=pid,operator='demo',summary=TAG+' 合成历史：领用 '+d['sn'],create_time=start)
    if end: add('wear_asset_audit',action='return',device_id=d['id'],assignment_id=aid,person_id=pid,operator='demo',summary=TAG+' 合成历史：归还 '+d['sn'],create_time=end)
    else:
        next(r for r in DATA['wear_device'] if r['id']==d['id'])['current_assignment_id']=aid
    return aid

for d in H[:29]+BELT[:9]: assign(d,d['person'],at(-31,8))
# 68 historical records on 17 other devices; each person's same-type intervals are disjoint.
hist=H[29:]+BELT[9:]
for cycle in range(4):
    used={1:set(),2:set()}
    for k,d in enumerate(hist):
        pool=[i for i,p in enumerate(P) if p['site']==d['site'] and i not in used[d['site']]]
        pi=pool[0]; used[d['site']].add(pi)
        assign(d,pi,at(-59+cycle*6,8),at(-58+cycle*6,17))
for d in hist[:8]:
    add('wear_device_site_transfer',device_id=d['id'],from_site_id=3-d['site'],to_site_id=d['site'],operator='demo',create_time=at(-65,10))
    add('wear_asset_audit',action='transfer',device_id=d['id'],operator='demo',summary=TAG+' 历史调拨至当前厂站（领用前）',create_time=at(-65,10))

# 24,000 points: 20 helmets, 30 days, 40 samples per day, all within holdings.
tracked=H[:14]+H[20:26]
for k,d in enumerate(tracked):
    for day in range(-29,1):
        for point in range(40):
            t=at(day,9,point*2)
            lat=36.12+(0.10 if d['site']==2 else 0)+0.001*math.sin(point/6+k/2)
            lng=117.12+(0.10 if d['site']==2 else 0)+0.001*math.cos(point/6+k/2)
            add('wear_device_sample',device_id=d['id'],occurred_at=t,received_at=t+timedelta(seconds=2),lat=round(lat,7),lng=round(lng,7),altitude='0',speed='1.0',battery=15 if k==5 else 85-point,online='1',location_quality='ok',create_time=t+timedelta(seconds=2))
    r=next(r for r in DATA['wear_device'] if r['id']==d['id'])
    r.update(online='1',battery=15 if k==5 else 46,last_reported_at=stamp(at(0,10,18)),last_telemetry_at=stamp(at(0,10,18)))

F=[]
for i,(site,name,mode,on) in enumerate([(1,'热电生产区边界（联调）','all_site',1),(1,'锅炉平台授权区（联调）','persons',1),(1,'检修备用区（停用联调）','all_site',0),(2,'风电北区边界（联调）','all_site',1),(2,'塔筒检修授权区（联调）','persons',1)]):
    base=0.10 if site==2 else 0
    lat=36.12+base;lng=117.12+base
    poly=[{'lng':round(lng+x,6),'lat':round(lat+y,6)} for x,y in [(-.004,-.004),(.004,-.004),(.004,.004),(-.004,.004)]]
    fid=add('wear_geo_fence',site_id=site,name=name,polygon_json=json.dumps(poly),enabled=on,apply_mode=mode,time_start='08:00' if mode=='persons' else None,time_end='18:00' if mode=='persons' else None,enter_enabled=1,leave_enabled=1,debounce_seconds=60,demo=1)
    F.append({'id':fid,'site':site})
    if mode=='persons':
        for pi in (range(9) if site==1 else range(27,36)): add('wear_geo_fence_person',fence_id=fid,person_id=P[pi]['id'])

tasks=[]
statuses=['in_progress']*7+['paused']*2+['ready']*5+['draft']*2+['ended']*12
for i,status in enumerate(statuses):
    site=1 if i%3!=2 else 2
    work='height' if i%3==0 else ('patrol' if i%3==1 else 'other')
    title=('锅炉平台检修' if work=='height' else '东区巡检') if site==1 else '风机设备巡检'
    start=at(-i if status=='ended' else (1+i%3 if status=='ready' else 0),8)
    end=start+timedelta(hours=12)
    owner=accounts[2 if site==1 else 27]
    members=([0,1,2,3] if i==0 else ([0,4,5,6] if i==1 else [x for x in (range(20) if site==1 else range(27,36))][i%4:i%4+3+i%3]))
    if status=='draft': members=[]
    ticket=f'QA-WP-{i+1:03}' if work=='height' and status!='draft' else None
    created=start-timedelta(days=1)
    tid=add('wear_work_task',site_id=site,title=f'{title}（联调{i+1:02}）',work_type=work,space_id=(floorA if work=='height' else areaA) if site==1 else floorB,planned_start=start if status!='draft' else None,planned_end=end if status!='draft' else None,actual_start=start if status in ('in_progress','paused','ended') else None,actual_end=end if status=='ended' else None,status=status,owner_user_id=owner[0],guardian_person_id=P[1 if site==1 else 28]['id'],ticket_required=int(work=='height'),ticket_no=ticket,ticket_status='provided' if ticket else ('unverified' if work=='height' else 'none'),demo=1,create_time=created)
    for pi in members: add('wear_work_task_member',task_id=tid,person_id=P[pi]['id'])
    for typ in (['helmet','belt'] if work=='height' else ['helmet']): add('wear_work_task_requirement',task_id=tid,type_code=typ)
    initial='draft' if status=='draft' else 'ready'
    add('wear_work_task_action',task_id=tid,action='create',actor='demo',reason=TAG+' 合成历史作业',from_status=None,to_status=initial,create_time=created)
    if status in ('in_progress','paused','ended'):
        add('wear_work_task_action',task_id=tid,action='start',actor='demo',reason=TAG+' 合成开始',from_status='ready',to_status='in_progress',create_time=start)
    if status in ('paused','ended'):
        add('wear_work_task_action',task_id=tid,action='pause' if status=='paused' else 'end',actor='demo',reason=TAG+' 合成作业操作',from_status='in_progress',to_status=status,create_time=start+timedelta(hours=3) if status=='paused' else end)
    tasks.append({'id':tid,'site':site,'members':members,'start':start,'end':end,'status':status})

# Most events are historical closed low-risk exercises. Only six new high-risk samples.
events=[]
for i in range(116):
    high=i>=110
    kind=['sos','fall','impact'][i%3] if high else ('geofence' if i%2==0 else 'realtime')
    d=H[i%29];p=P[d['person']];site=d['site']
    status=('pending_review' if i>=114 else 'closed') if high else ('closed' if i<90 else ['open','claimed','handling'][i%3])
    t=at(-1-i%28,11,i%30) if status=='closed' else NOW-timedelta(minutes=90+i)
    owner=accounts[2 if site==1 else 27];reviewer=accounts[6 if site==1 else 30]
    chain=[]
    if status!='open': chain=[('claim','open','claimed')]
    if status in ('handling','pending_review','closed'): chain.append(('handle','claimed','pending_review' if high else 'handling'))
    if status=='closed': chain.append(('close','pending_review' if high else 'handling','closed'))
    task=next((task for task in tasks if task['site']==site and d['person'] in task['members'] and task['start']<=t<=task['end'] and task['status'] in ('ended','in_progress','paused')),None)
    eid=add('wear_safety_event',source='simulator',source_event_id=TAG+('-SPECIAL-' if high else '-DAY-')+str(i+1),event_type=kind,severity='high' if high else 'low',status=status,occurred_at=t,received_at=t+timedelta(seconds=1),person_id=p['id'],person_code=p['code'],person_name=p['name'],device_id=d['id'],sn=d['sn'],site_id=site,location_lat=36.12+(0.1 if site==2 else 0),location_lng=117.12+(0.1 if site==2 else 0),location_quality='ok',claimant_user_id=owner[0] if status!='open' else None,task_id=task['id'] if task else None,task_match='matched' if task else 'none',fence_id=(F[0]['id'] if site==1 else F[3]['id']) if kind=='geofence' else None,fence_action='enter' if kind=='geofence' else None,demo=1,version=1+len(chain),create_time=t,update_time=t+timedelta(minutes=len(chain)*5))
    for step,(action,old,new) in enumerate(chain):
        add('wear_event_action',event_id=eid,action=action,actor='demo',reason=TAG+(' 专项演练：' if high else ' 合成历史：')+{'claim':'值班认领','handle':'现场核查记录','close':'复核完成' if high else '核查后关闭'}[action],from_status=old,to_status=new,create_time=t+timedelta(minutes=(step+1)*5))
    for uid in [owner[0],reviewer[0],accounts[8 if site==1 else 28][0]]: add('wear_event_inbox',event_id=eid,user_id=uid,acked=int(status=='closed'),create_time=t+timedelta(seconds=1))
    events.append({'id':eid,'device':d,'type':kind,'time':t,'status':status})

for i in range(40):
    d=H[i%29]
    if d['model']==2:d=H[0]
    t=at(-1-i%28,14,i%50)
    status=['ended','failed','timed_out'][i%3]
    add('wear_call_session',kind='single',device_id=d['id'],sn=d['sn'],person_id=P[d['person']]['id'],site_id=d['site'],requester_user_id=accounts[2 if d['site']==1 else 27][0],status=status,channel_name=TAG+'-CALL-'+str(i+1),video=int(i%4==0 and d['model']==1),demo=1,expires_at=t+timedelta(seconds=90),started_at=t,ended_at=t+timedelta(seconds=90 if status=='timed_out' else 30),fail_reason=TAG+' 合成通话历史；未接通真实设备',create_time=t)

def sqlval(v):
    if v is None:return 'NULL'
    if isinstance(v,(int,float)):return str(v)
    return "'"+str(v).replace('\\','\\\\').replace("'","''")+"'"

out=['SET NAMES utf8mb4;','SET SESSION sql_mode=\'STRICT_ALL_TABLES,NO_ENGINE_SUBSTITUTION\';','START TRANSACTION;']
for table,records in DATA.items():
    columns=list(dict.fromkeys(k for r in records for k in r))
    # Missing columns use DEFAULT, preserving nullable/default semantics.
    for offset in range(0,len(records),250):
        vals=[ '('+','.join(sqlval(r[c]) if c in r else 'DEFAULT' for c in columns)+')' for r in records[offset:offset+250] ]
        out.append('INSERT INTO `'+table+'` ('+','.join('`'+c+'`' for c in columns)+') VALUES\n'+',\n'.join(vals)+';')
out.append('COMMIT;')
(B/'导入.sql').write_text('\n'.join(out),'utf-8')
save(B/'批次清单.json',{'batch':TAG,'generatedAt':NOW.isoformat(),'counts':{t:len(rs) for t,rs in DATA.items()},'ids':{t:[r[AUTO[t]] for r in rs] for t,rs in DATA.items() if t in AUTO},'corePeople':P[:5],'helmets':H,'belts':BELT,'accounts':[{k:v for k,v in a.items() if k!='password'} for a in credentials]})
print(json.dumps({'batch':TAG,'sqlBytes':(B/'导入.sql').stat().st_size,'counts':{t:len(rs) for t,rs in DATA.items()}},ensure_ascii=False))
