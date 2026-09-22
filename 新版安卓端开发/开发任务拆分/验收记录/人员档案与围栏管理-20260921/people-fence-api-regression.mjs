import {readFile,writeFile} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
const fixture=await readFile('C:/Users/qiyue/Desktop/开发项目/新版安卓端开发/音视频网页联调/test/alarms-browser.mjs','utf8');
const password=process.env.LAB_TEST_PASSWORD||fixture.match(/password = process.env.LAB_TEST_PASSWORD \|\| '([^']+)'/)?.[1];
const base='http://127.0.0.1:18084';
const tokens={}; const checks=[];
for(const name of ['admin','siteA_duty','siteA_team_lead','siteB_duty']) {
  const r=await(await fetch(base+'/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({username:name,password})})).json();
  if(!r.token) throw Error('Login unavailable: '+name); tokens[name]=r.token;
}
function sql(query) {
  const r=spawnSync('docker',['exec','-i','melhat-mysql','sh','-c','MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot -N -B --default-character-set=utf8mb4 -D melhat_local'],{input:query,encoding:'utf8'});
  if(r.status!==0) throw Error('Fixture SQL failed: '+r.stderr); return r.stdout.trim();
}

const code='QAM'+Date.now(); let site,person,contractor,user;const requests=[];
async function api(path,body,method,who='admin',expected=200) {
 const r=await(await fetch(base+path,{method:method||(body===undefined?'GET':'POST'),headers:{...(who?{Authorization:'Bearer '+tokens[who]}:{}),'X-Site-Id':String(site),'Content-Type':'application/json'},...(body===undefined?{}:{body:JSON.stringify(body)})})).json();
 assert.equal(r.code,expected,path+' '+r.msg);return r.data;
}
try {
 site=Number(sql(`INSERT INTO wear_site(site_code,name,status,create_by,create_time) VALUES ('${code}','人员围栏回归厂站','0','qa-mgmt',NOW()); SELECT LAST_INSERT_ID();`));
 assert.ok(site>2);
 const team=await api('/api/v1/teams',{name:code+'班组',siteId:String(site)});
 contractor=await api('/api/v1/contractors',{name:code+'承包商'});
 const initial={personCode:code,name:'人员围栏测试',teamId:team.id,contractorId:contractor.id,siteIds:[String(site)],validFrom:'2026-01-01',validTo:'2027-12-31'};
 person=await api('/api/v1/people',initial);
 person=await api('/api/v1/people/'+person.id,{...initial,name:'人员围栏测试修改',version:person.version},'PUT');
 assert.equal(person.name,'人员围栏测试修改');assert.equal(person.teamId,team.id);assert.equal(person.validTo,'2027-12-31');
 await api('/api/v1/people/'+person.id,{...initial,version:0},'PUT','admin',409);checks.push('person create edit validity and stale edit protection');
 await api('/api/v1/people/'+person.id+'/status',{status:'1',version:person.version},'PUT');
 person=await api('/api/v1/people/'+person.id);assert.equal(person.status,'1');
 await api('/api/v1/people/'+person.id+'/status',{status:'0',version:person.version},'PUT');checks.push('person disable and restore');
 await api('/api/v1/teams/'+team.id,{name:code+'修改班组'},'PUT');
 await api('/api/v1/contractors/'+contractor.id,{status:'1'},'PUT');
 await api('/api/v1/contractors/'+contractor.id,{status:'0'},'PUT');checks.push('team and contractor maintenance');
 const model=sql("SELECT id FROM wear_product_model WHERE del_flag='0' LIMIT 1;");
 const device=await api('/api/v1/devices',{manufacturerCode:'QA',sn:code,modelId:model,siteId:String(site)});
 const assignment=await api('/api/v1/assignments',{personId:person.id,deviceId:device.id,idempotencyKey:code+'-issue'});
 const same=await api('/api/v1/assignments',{personId:person.id,deviceId:device.id,idempotencyKey:code+'-issue'});assert.equal(same.id,assignment.id);
 assert.equal((await api('/api/v1/people/'+person.id+'/equipment')).length,1);
 await api('/api/v1/assignments/'+assignment.id+'/return',{reason:'QA return',idempotencyKey:code+'-return'});
 assert.equal((await api('/api/v1/people/'+person.id+'/equipment')).length,0);checks.push('equipment assign idempotent retry and return');
 const fenceBody={name:code,polygon:[{lat:31,lng:121},{lat:31.001,lng:121},{lat:31.001,lng:121.001}],applyMode:'persons',personIds:[person.id],enabled:true,enterEnabled:true,leaveEnabled:true,debounceSeconds:60,timeStart:'08:00',timeEnd:'18:00'};
 let fence=await api('/api/v1/fences',fenceBody);
 fence=await api('/api/v1/fences/'+fence.id,{...fenceBody,name:code+'编辑',enabled:false,version:fence.version},'PUT');
 assert.equal(fence.enabled,false);assert.equal(fence.polygon.length,3);assert.deepEqual(fence.personIds,[person.id]);
 await api('/api/v1/fences/'+fence.id,{...fenceBody,version:0},'PUT','admin',409);
 await api('/api/v1/fences',{...fenceBody,polygon:[{lat:100,lng:121},{lat:31,lng:121},{lat:32,lng:122}]},'POST','admin',400);
 checks.push('fence point save edit enabled state and geometry validation');
 await api('/api/v1/fences/map-tiles/30/0/0',undefined,'GET','admin',400);
 await api('/api/v1/fences/map-tiles/16/1/2',undefined,'GET','siteB_duty',403);checks.push('map tile site authorization');
 const headers={Authorization:'Bearer '+tokens.admin,'X-Site-Id':String(site)};
 let response=await fetch(base+'/api/v1/people/import-template',{headers});let bytes=Buffer.from(await response.arrayBuffer());assert.equal(bytes.subarray(0,2).toString(),'PK');
 response=await fetch(base+'/api/v1/people/export',{method:'POST',headers:{...headers,'Content-Type':'application/json'},body:'{}'});bytes=Buffer.from(await response.arrayBuffer());assert.equal(bytes.subarray(0,2).toString(),'PK');
 const form=new FormData();form.append('file',new Blob([bytes]),'qa.xlsx');form.append('updateExisting','true');
 const imported=await(await fetch(base+'/api/v1/people/import',{method:'POST',headers,body:form})).json();assert.equal(imported.code,200);assert.equal(imported.data.errors.length,0);assert.equal(imported.data.updated,1);checks.push('xlsx template export and import roundtrip');
 user=Number(sql(`INSERT INTO sys_user(dept_id,user_name,nick_name,user_type,password,status,del_flag,create_by,create_time) SELECT 100,'${code}','账号找回测试','00',password,'0','0','qa-mgmt',NOW() FROM sys_user WHERE user_id=1; SELECT LAST_INSERT_ID();`));
 let login=await(await fetch(base+'/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({username:code,password})})).json();assert.ok(login.token);const oldToken=login.token;
 const request=await api('/api/v1/account-recovery/requests',{identifier:code,realName:'账号找回测试',contact:'13800000000',reason:'QA 忘记账号'},'POST',null);requests.push(request.id);
 await api('/api/v1/account-recovery/requests',undefined,'GET','siteA_duty',403);
 const candidates=await api('/api/v1/account-recovery/accounts?q='+code);assert.equal(String(candidates[0].id),String(user));
 const nextPassword='Qa'+String(Date.now()).slice(-10);
 await api('/api/v1/account-recovery/requests/'+request.id+'/approve',{targetUserId:String(user),newPassword:nextPassword,reason:'QA 核实身份'});
 await api('/api/v1/account-recovery/requests/'+request.id+'/approve',{targetUserId:String(user),newPassword:nextPassword,reason:'QA 重复'},'POST','admin',409);
 login=await(await fetch(base+'/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({username:code,password:nextPassword})})).json();assert.ok(login.token);
 const revoked=await(await fetch(base+'/api/v1/me',{headers:{Authorization:'Bearer '+oldToken}})).json();assert.equal(revoked.code,401);
 checks.push('public recovery admin-only approval password changed old token revoked duplicate blocked');
 const rejected=await api('/api/v1/account-recovery/requests',{identifier:code,realName:'账号找回测试',contact:'13800000000',reason:'QA 驳回'},'POST',null);requests.push(rejected.id);
 await api('/api/v1/account-recovery/requests/'+rejected.id+'/reject',{reason:'QA 身份无法核实'});
 assert.equal(sql(`SELECT status FROM wear_account_recovery WHERE id='${rejected.id}';`),'rejected');checks.push('rejection retained in audit');
 await writeFile('C:/melhat-runtime/people-fence-api-results.json',JSON.stringify({passed:checks.length,checks},null,2));console.log(JSON.stringify({passed:checks.length,checks},null,2));
} finally {
 if(site && sql(`SELECT site_code FROM wear_site WHERE id=${site};`)===code) {
  sql(`DELETE p FROM wear_geo_fence_person p JOIN wear_geo_fence f ON f.id=p.fence_id WHERE f.site_id=${site}; DELETE FROM wear_geo_fence WHERE site_id=${site}; DELETE FROM wear_assignment WHERE site_id=${site}; DELETE FROM wear_device WHERE site_id=${site}; DELETE ps FROM wear_person_site ps JOIN wear_person p ON p.id=ps.person_id WHERE p.person_code='${code}'; DELETE FROM wear_person WHERE person_code='${code}'; DELETE FROM wear_team WHERE site_id=${site}; DELETE FROM wear_contractor WHERE name='${code}承包商'; DELETE FROM wear_account_recovery WHERE identifier='${code}'; DELETE FROM sys_user WHERE user_name='${code}' AND create_by='qa-mgmt'; DELETE FROM wear_site WHERE id=${site};`);
  console.log('Temporary QA records removed.');
 }
}

