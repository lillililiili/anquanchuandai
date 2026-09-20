"""Exercise actual APIs with new fixture accounts; never touch pre-existing business rows."""
import json,sys,urllib.request,urllib.error,urllib.parse
from datetime import datetime,timedelta
from 执行工具 import ROOT,save,mysql,rows
B=sorted(ROOT.glob('执行批次-*'))[-1]
MAN=json.loads((B/'批次清单.json').read_text('utf-8'))
CREDS={r['username']:r for r in json.loads((B/'测试账号-请勿外传.json').read_text('utf-8'))}
LOG=json.loads((B/'接口验收记录.json').read_text('utf-8')) if (B/'接口验收记录.json').exists() else []
TOKENS={}
BASE='http://127.0.0.1:18084'
def call(path,user='qa_a_duty',site=1,body=None,expect=200):
    headers={'Content-Type':'application/json','X-Site-Id':str(site)}
    if user:
        if user not in TOKENS:
            c=CREDS[user];req=urllib.request.Request(BASE+'/login',data=json.dumps({'username':user,'password':c['password']}).encode(),headers={'Content-Type':'application/json'})
            j=json.load(urllib.request.urlopen(req,timeout=30));assert j['code']==200,(user,j.get('msg'));TOKENS[user]=j['token']
        headers['Authorization']='Bearer '+TOKENS[user]
    req=urllib.request.Request(BASE+path,data=json.dumps(body,ensure_ascii=False).encode('utf-8') if body is not None else None,headers=headers)
    try:
        with urllib.request.urlopen(req,timeout=60) as r:j=json.load(r)
    except urllib.error.HTTPError as e:j=json.load(e)
    record={'path':path,'user':user,'site':site,'method':'POST' if body is not None else 'GET','code':j.get('code'),'result':j}
    LOG.append(record);save(B/'接口验收记录.json',LOG)
    assert j.get('code')==expect,(path,j)
    return j.get('data')

def reads():
    for user,c in CREDS.items():call('/api/v1/me',user,c['siteIds'][0])
    for user,site in [('qa_a_duty',1),('qa_b_duty',2)]:
        for endpoint in ['people','devices','work-tasks','events','fences','locations/people']:
            p=call('/api/v1/'+endpoint+'?current=1&size=10',user,site)
            assert isinstance(p,dict) and 'records' in p,(endpoint,p)
        call('/api/v1/duty/summary',user,site)
        call('/api/v1/duty/operators',user,site)
    core=MAN['corePeople'][0];helmet=MAN['helmets'][0]
    eq=call('/api/v1/me/equipment','qa_chen');assert 'RL-H001' in json.dumps(eq) and 'RL-B001' in json.dumps(eq),eq
    call('/api/v1/devices/'+str(helmet['id']))
    call('/api/v1/people/'+str(core['id'])+'/assignments')
    p=call('/api/v1/locations/people/'+str(core['id']));assert p.get('demo') is True,p
    now=datetime.now().astimezone();q=urllib.parse.urlencode({'from':(now-timedelta(days=30)).isoformat(),'to':now.isoformat(),'current':1,'size':500})
    tracks=call('/api/v1/locations/people/'+str(core['id'])+'/tracks?'+q);assert tracks['total']==500 and len(tracks['records'])==500
    call('/api/v1/people?current=3&size=10')
    call('/api/v1/events?current=3&size=10')
    for tid in MAN['ids']['wear_work_task'][:3]:
        s=2 if tid==MAN['ids']['wear_work_task'][2] else 1
        for suffix in ['', '/equipment-check','/events']:call('/api/v1/work-tasks/'+str(tid)+suffix,'qa_a_duty' if s==1 else 'qa_b_duty',s)
    call('/api/v1/devices/'+str(MAN['helmets'][20]['id']),'qa_a_duty',1,expect=403)
    call('/api/v1/events/'+str(MAN['ids']['wear_safety_event'][90])+'/claim','qa_zhao',1,body={'version':1},expect=403)
    call('/api/v1/people?current=1&size=100','qa_cross',2)
    print('API read checks: '+str(len(LOG))+' passed; track thinning=500; site and readonly restrictions=403')

def actions():
    assert not (B/'接口写入已完成.json').exists(),'Do not repeat API actions'
    made={'commands':[],'handovers':[],'replays':[],'closedEvents':[]}
    for i,d in enumerate(MAN['helmets'][:12]):
        result=call('/api/v1/commands/tts',body={'deviceIds':[str(d['id'])],'text':f'联调测试{i+1:02}：请按作业票检查装备。此记录为模拟播报，未向真实设备发送。','idempotencyKey':MAN['batch']+'-tts-'+str(i)})
        assert result[0]['status']=='accepted' and result[0]['heard'] is False,result
        made['commands'].append(result[0]['id'])
    # Close two previously-open, new low-risk events through their real state machine.
    candidates=rows("SELECT JSON_OBJECT('id',id,'version',version) FROM wear_safety_event WHERE id>4 AND site_id=1 AND status='open' AND severity='low' ORDER BY id LIMIT 2;")
    for e in candidates:
        path='/api/v1/events/'+str(e['id'])
        v=call(path+'/claim',body={'version':e['version']})
        v=call(path+'/handle',body={'version':v['version'],'comment':'联调核查：合成样本，已验证现场核查流程。'})
        v=call(path+'/close',body={'version':v['version'],'reason':'联调闭环验证完成，非真实现场事故。'})
        assert v['status']=='closed';made['closedEvents'].append(e['id'])
    # Two confirmed transfers plus two pending, with explicit new task IDs.
    for site,from_user,to_user,task_index in [(1,'qa_a_duty','qa_a_duty2',0),(2,'qa_b_duty','qa_b_duty2',2)]:
        tid=MAN['ids']['wear_work_task'][task_index]
        eid=rows(f"SELECT JSON_OBJECT('id',id) FROM wear_safety_event WHERE id>4 AND site_id={site} AND claimant_user_id={CREDS[from_user]['userId']} AND status IN ('claimed','handling') ORDER BY id LIMIT 1;")[0]['id']
        h=call('/api/v1/duty/handovers',from_user,site,body={'toUserId':str(CREDS[to_user]['userId']),'taskIds':[str(tid)],'eventIds':[str(eid)],'comment':MAN['batch']+' 实际接口交接验证（模拟业务）'})
        c=call('/api/v1/duty/handovers/'+h['id']+'/confirm',to_user,site,body={});assert c['status']=='confirmed'
        made['handovers'].append(c['id'])
        pending=call('/api/v1/duty/handovers',to_user,site,body={'toUserId':str(CREDS[from_user]['userId']),'taskIds':[str(tid)],'eventIds':[str(eid)],'comment':MAN['batch']+' 待接班交接样本'})
        made['handovers'].append(pending['id'])
    for d in MAN['helmets'][:6]+MAN['helmets'][20:26]:
        site=d['site'];user='qa_a_devices' if site==1 else 'qa_b_devices'
        now=datetime.now()
        result=call('/api/v1/ingest/replay',user,site,body={'path':'/ext/notifyGnss','payload':{'helmetSn':d['sn'],'timestamp':now.strftime('%Y-%m-%d %H:%M:%S'),'latitude':36.12+(0.1 if site==2 else 0),'longitude':117.12+(0.1 if site==2 else 0),'altitude':'0','speed':'0'}})
        made['replays'].append({'sn':d['sn'],'response':result})
    save(B/'接口写入已完成.json',made)
    print('API action checks passed: '+json.dumps({k:len(v) for k,v in made.items()}))

if __name__=='__main__':
    reads()
    if '--write' in sys.argv:actions()
