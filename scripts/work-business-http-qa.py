"""Exercise real HTTP on a disposable compatibility clone; never authenticate daily service."""
import argparse, base64, datetime as dt, hashlib, importlib.util, json, os, pathlib, secrets, subprocess, time, urllib.request, urllib.error, uuid, zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
BACKEND = ROOT / '后端代码/melhat_server-dev'
spec = importlib.util.spec_from_file_location('qa', BACKEND / 'local-dev/wearable-compatible-qa.py')
qa = importlib.util.module_from_spec(spec); spec.loader.exec_module(qa)
patch = qa.patch

def run(directory):
    directory = pathlib.Path(directory).resolve()
    assert directory.parent == BACKEND / 'build'
    resources = patch.read_json(directory / 'qa-resources.json')
    smoke = patch.read_json(directory / 'qa-anonymous-smoke.json')
    assert smoke['passed'] and resources['backend'].startswith('wearable-compatible-qa-')
    private = directory / 'qa-private'; private.mkdir(exist_ok=True)
    daily = patch.inspect('melhat-backend')
    original = patch.inspect(resources['backend'])
    assert original['Image'] == smoke['imageId']
    password = secrets.token_urlsafe(24)
    # A fresh password is written only to the cloned account. No live credentials are read.
    java = pathlib.Path(os.environ.get('JAVA_HOME', r'C:/Users/19221/.jdks/temurin-17')) / 'bin'
    candidates = list((pathlib.Path.home() / '.m2/repository/org/springframework/security/spring-security-crypto').glob('*/*.jar'))
    logging = list((pathlib.Path.home() / '.m2/repository/org/springframework/spring-jcl').glob('*/*.jar'))
    assert candidates and logging
    classpath = os.pathsep.join(map(str, [candidates[-1], logging[-1]]))
    source = private / 'QaHash.java'
    source.write_text('import java.io.*; import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder; public class QaHash { public static void main(String[] args)throws Exception { System.out.print(new BCryptPasswordEncoder().encode(new BufferedReader(new InputStreamReader(System.in)).readLine())); }}', encoding='utf-8')
    subprocess.run([str(java/'javac.exe'), '-cp', classpath, str(source)], check=True, capture_output=True)
    digest = subprocess.run([str(java/'java.exe'), '-cp', str(private)+os.pathsep+classpath, 'QaHash'], input=password.encode(), capture_output=True, check=True).stdout.decode()
    assert digest.startswith('$2')
    if original['State']['Running']: patch.docker('stop', '--time', '30', resources['backend'])
    http_name = resources['backend'] + '-http'
    reuse=False
    if resources.get('httpBackend'):
        existing=patch.inspect(resources['httpBackend']);assert existing['Name']=='/'+http_name and existing['Image']==original['Image']
        patch.docker('stop','--time','30',http_name)
        if existing['HostConfig'].get('PortBindings'):
            patch.docker('rename',http_name,http_name+'-unused-port-'+uuid.uuid4().hex[:6])
        else: reuse=True
    qa.clone_sql(resources['mysql'], ("UPDATE wearable_account SET body=JSON_SET(body,'$.passwordHash','"+digest+"') WHERE id='demo-system';").encode())
    args = ['run','-d','--name',http_name,'--network',resources['network'],'-v',resources['backendVolume']+':/data']
    for value in original['Config']['Env']: args += ['-e', value]
    if reuse: patch.docker('start',http_name)
    else: patch.docker(*args, original['Image'], *original['Config']['Cmd'])
    resources['httpBackend'] = http_name; patch.write_json(directory/'qa-resources.json', resources)
    base = 'http://127.0.0.1:18085'; calls = []; checks = []
    def request(method, path, body=None, token=None, expected=200, raw=False):
        data = body if raw else (None if body is None else json.dumps(body, ensure_ascii=False).encode())
        headers = {'Content-Type':'image/png' if raw else 'application/json'}
        if token: headers['X-Wearable-Token'] = token
        try:
            response = urllib.request.urlopen(urllib.request.Request(base+path, data=data, headers=headers, method=method), timeout=30)
            status, payload = response.status, response.read()
        except urllib.error.HTTPError as error: status, payload = error.code, error.read()
        calls.append({'method':method,'path':path,'status':status})
        try: parsed = json.loads(payload) if payload else {}
        except ValueError: parsed = {'message':'Response was not JSON'}
        assert status == expected, (method,path,status,expected,parsed.get('errorCode'),parsed.get('message'))
        return parsed
    try:
        deadline = time.monotonic()+100
        while True:
            try:
                if request('GET','/captchaImage')['code']==200: break
            except (OSError, AssertionError):
                if time.monotonic()>deadline: raise RuntimeError('QA HTTP backend did not become healthy')
                time.sleep(1)
        admin = request('POST','/api/admin/v1/login', {'username':'demo-system','password':password})['token']
        pc = request('POST','/api/guardian/v1/login', {'account':'demo-system','password':password})['token']
        patch.write_json(private/'browser-session.private.json',{'baseUrl':base,'adminToken':admin,'pcToken':pc,'password':password})
        def a(method,path,body=None,expected=200): return request(method,'/api/admin/v1/'+path,body,admin,expected)
        def g(method,path,body=None,expected=200,token=pc): return request(method,'/api/guardian/v1/'+path,body,token,expected)
        def command(kind,data): return a('POST','execute',{'type':kind,'input':{'operationId':str(uuid.uuid4()),'siteId':'site-1',**data}})['data']
        config = a('GET','business-config'); initial_watch=config['simulatedWatchVisible']; assert config['workBusinessEnabled'] is True
        def toggle(value):
            current=a('GET','business-config'); return a('PATCH','business-config',{'workBusinessEnabled':value,'expectedVersion':current['version']})
        suffix=uuid.uuid4().hex[:8]
        persons=[command('people.create',{'data':{'name':'隔离核验人员'+str(i),'code':'WB-'+suffix+'-'+str(i),'remark':'仅隔离克隆验收'}}) for i in range(3)]
        master=a('GET','state')['state']; people=[next(p for p in master['people'] if p['id']==row['id']) for row in persons]
        pids=[p['portalId'] for p in people]
        account=command('accounts.create',{'relatedVersions':{people[0]['id']:people[0]['version']},'data':{'name':'隔离手机用户','loginName':'wb-'+suffix,'password':password,'personId':people[0]['id'],'bindings':[{'roleId':'mobile-user'}]}})
        mobile=g('POST','mobile/login',{'account':account['loginName'],'password':password},token=None)['token']
        ordinary=command('accounts.create',{'data':{'name':'隔离值守用户','loginName':'wb-duty-'+suffix,'password':password,'bindings':[{'roleId':'duty'}]}})
        ordinary_token=request('POST','/api/admin/v1/login',{'username':ordinary['loginName'],'password':password})['token']
        a('GET','works/options?siteId=site-1')
        request('GET','/api/admin/v1/works',token=ordinary_token,expected=403)
        request('PATCH','/api/admin/v1/business-config',{'workBusinessEnabled':False,'expectedVersion':config['version']},ordinary_token,403)
        checks.append('system-only-api-and-default-enabled')
        now=dt.datetime.now(dt.timezone.utc)
        body={'requestId':str(uuid.uuid4()),'siteId':'site-1','name':'隔离跨日检修','area':'隔离平台','plannedStartAt':(now-dt.timedelta(hours=2)).isoformat(),'plannedEndAt':(now+dt.timedelta(hours=30)).isoformat(),'leader':pids[0],'supervisor':pids[1],'members':[pids[0]],'remarks':'高处作业风险说明原文保留'}
        work=a('POST','works',body); assert a('POST','works',body)==work and set(work['members'])==set(pids[:2])
        a('POST','works',{**body,'name':'重用请求编号'},409)
        def act(w,action,expected=200): return a('POST','works/'+w['id']+'/actions',{'requestId':str(uuid.uuid4()),'expectedVersion':w['version'],'action':action},expected)
        work=act(work,'start'); assert work['status']=='进行中'
        conflict=a('POST','works',{**body,'requestId':str(uuid.uuid4()),'name':'冲突检修'}); act(conflict,'start',409); conflict=act(conflict,'cancel')
        a('PATCH','works/'+work['id'],{'requestId':str(uuid.uuid4()),'expectedVersion':1,'remarks':'旧版本'},409)
        event=g('POST','sos',{'requestId':str(uuid.uuid4()),'siteId':'site-1','description':'隔离手机求助'},token=mobile)
        assert event['workId']==work['id'] and event['source']=='manual_sos'; snapshot=event['snapshot'].copy()
        work=a('PATCH','works/'+work['id'],{'requestId':str(uuid.uuid4()),'expectedVersion':work['version'],'name':'修改后的检修','supervisor':pids[2]})
        assert g('GET','events/'+event['id'])['snapshot']==snapshot
        assert any(w['id']==work['id'] for w in g('GET','mobile/context?siteId=site-1',token=mobile)['works'])
        checks.append('cross-day-idempotency-conflict-version-and-historical-snapshot')
        def event_command(e,action,extra=None): return g('POST','events/'+e['id']+'/'+action,{'requestId':str(uuid.uuid4()),'expectedVersion':e['version'],**(extra or {})})
        event=event_command(event,'claim'); event=event_command(event,'verification-draft',{'situation':'高处作业现场草稿','conclusion':'暂无法确认'})
        off=toggle(False); assert off['simulatedWatchVisible']==initial_watch
        a('PATCH','business-config',{'workBusinessEnabled':True,'expectedVersion':config['version']},409)
        a('POST','works',{**body,'requestId':str(uuid.uuid4())},409); act(work,'finish',409)
        assert a('GET','works/'+work['id'])['status']=='进行中'
        state=g('GET','snapshot')['state']; assert not state.get('works')
        hidden=g('GET','events/'+event['id']); assert 'workId' not in hidden and 'workName' not in hidden['snapshot'] and hidden['draft']['situation']=='高处作业现场草稿'
        offevent=g('POST','sos',{'requestId':str(uuid.uuid4()),'siteId':'site-1'},token=mobile); assert 'workId' not in offevent
        assert not g('GET','mobile/context?siteId=site-1',token=mobile).get('works')
        photo='upload-'+str(uuid.uuid4())
        png=base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==')
        request('PUT','/api/guardian/v1/files/'+photo,png,pc,raw=True)
        event=event_command(hidden,'observations',{'situation':'关闭模式现场补充','photoIds':[photo]})
        event=event_command(event,'verification',{'situation':'高处作业已现场确认','conclusion':'需现场处理','measures':'完成现场处置'})
        assert event['status']=='已核验' and 'workId' not in event
        assert g('GET','events/'+event['id'],token=mobile)['status']=='已核验'
        media=g('GET','snapshot')['state']['media']; assert any(m.get('blobId')==photo and 'workId' not in m for m in media)
        checks.append('disabled-readonly-sos-claim-draft-photo-verification-cross-client')
        toggle(True); restored=g('GET','events/'+event['id']); assert restored['workId']==work['id'] and restored['snapshot']==snapshot
        assert not g('GET','events/'+offevent['id']).get('workId'); assert a('GET','works/'+work['id'])['status']=='进行中'
        work=act(work,'finish'); assert work['status']=='已结束'; act(work,'cancel',409)
        overdue=a('POST','works',{**body,'requestId':str(uuid.uuid4()),'name':'过期登记','plannedStartAt':(now-dt.timedelta(hours=3)).isoformat(),'plannedEndAt':(now-dt.timedelta(hours=1)).isoformat()}); act(overdue,'start',409); act(overdue,'cancel')
        checks.append('reenable-history-no-retroactive-link-manual-finish-and-expiry')
        patch.write_json(private/'browser-session.private.json',{'baseUrl':base,'adminToken':admin,'pcToken':pc,'mobileToken':mobile,'account':account['loginName'],'password':password,'workId':work['id'],'eventId':event['id'],'people':pids})
        after=patch.inspect('melhat-backend'); assert after['Id']==daily['Id'] and after['Image']==daily['Image']
        result={'passed':True,'checks':checks,'requests':calls,'dailyContainerUnchanged':True,'dailyApplicationLoginAttempted':False,'qaBaseUrl':base,'httpBackend':http_name}
    except Exception as error:
        result={'passed':False,'checks':checks,'requests':calls,'error':str(error)}
        patch.write_json(directory/'work-business-http-qa.json',result)
        raise
    patch.write_json(directory/'work-business-http-qa.json',result)
    print(json.dumps({'passed':True,'checks':checks,'evidence':str(directory/'work-business-http-qa.json')},ensure_ascii=False))

if __name__=='__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('--directory',required=True); args=parser.parse_args();run(args.directory)
