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
const code='QA-DUTY-'+Date.now(); let site;
async function api(name,path,body,expected=200) {
 const r=await(await fetch(base+path,{method:body===undefined?'GET':'POST',headers:{Authorization:'Bearer '+tokens[name],'X-Site-Id':String(site),'Content-Type':'application/json'},...(body===undefined?{}:{body:JSON.stringify(body)})})).json();
 assert.equal(r.code,expected,name+' '+path+' '+r.msg);return r.data;
}
try {
 site=Number(sql(`INSERT INTO wear_site(site_code,name,status,create_by,create_time) VALUES ('${code}','值班回归临时厂站','0','qa-duty',NOW()); SELECT LAST_INSERT_ID();`));
 assert.ok(Number.isSafeInteger(site)&&site>2);
 sql(`INSERT INTO wear_site_account(site_id,user_id,status,create_by,create_time) VALUES (${site},109,'0','qa-duty',NOW()),(${site},113,'0','qa-duty',NOW());`);
 let operators=await api('siteA_duty','/api/v1/duty/operators'); assert.ok(operators.some(x=>x.userName==='admin')); checks.push('admin candidate without duty grant');
 await api('siteB_duty','/api/v1/duty/shifts',undefined,403);checks.push('cross-site read blocked');
 let h=await api('siteA_duty','/api/v1/duty/handovers',{toUserId:'1',comment:'QA init'});
 await api('admin',`/api/v1/duty/handovers/${h.id}/confirm`,{});
 let page=await api('admin','/api/v1/duty/shifts');assert.equal(page.currentDuty.userId,'1');checks.push('admin accepts without duty role');
 h=await api('admin','/api/v1/duty/handovers',{toUserId:'109'});
 await api('siteA_duty',`/api/v1/duty/handovers/${h.id}/cancel`,{reason:'not sender'},403);
 await api('admin',`/api/v1/duty/handovers/${h.id}/cancel`,{reason:'QA cancel'});checks.push('cancel permissions and sender cancellation');
 await api('siteA_duty',`/api/v1/duty/handovers/${h.id}/confirm`,{},409);
 h=await api('admin','/api/v1/duty/handovers',{toUserId:'109'});await api('siteA_duty',`/api/v1/duty/handovers/${h.id}/confirm`,{});
 page=await api('admin','/api/v1/duty/shifts');assert.equal(page.currentDuty.userId,'109');assert.equal(page.records.length,2);assert.equal(page.records[1].endedAt,page.records[0].startedAt);checks.push('continuous shift boundaries');
 const shift=page.currentDuty.id;
 const eventIds=sql(`INSERT INTO wear_safety_event(source,source_event_id,event_type,severity,status,occurred_at,received_at,site_id,claimant_user_id,demo,create_by) VALUES ('simulator','${code}-1','impact','high','handling',NOW(),NOW(),${site},109,1,'qa-duty'),('simulator','${code}-2','fall','high','pending_review',NOW(),NOW(),${site},109,1,'qa-duty'); SELECT id FROM wear_safety_event WHERE site_id=${site} ORDER BY id;`).split('\n');
 sql(`INSERT INTO wear_work_task(site_id,title,work_type,status,owner_user_id,demo,create_by) VALUES (${site},'QA duty transfer','normal','in_progress',109,1,'qa-duty');`);
 h=await api('siteA_duty','/api/v1/duty/handovers',{toUserId:'113'});
 await api('siteA_duty','/api/v1/duty/takeover',{expectedShiftId:shift,reason:'forbidden'},403);
 await api('admin','/api/v1/duty/takeover',{expectedShiftId:'999999',reason:'stale'},409);
 await api('admin','/api/v1/duty/takeover',{expectedShiftId:shift,reason:''},400);
 await api('admin','/api/v1/duty/takeover',{expectedShiftId:shift,reason:'QA admin takeover'});
 assert.equal(sql(`SELECT COUNT(*) FROM wear_safety_event WHERE site_id=${site} AND claimant_user_id=1;`),'2');
 assert.equal(sql(`SELECT owner_user_id FROM wear_work_task WHERE site_id=${site};`),'1');
 assert.equal(sql(`SELECT status FROM wear_duty_handover WHERE id=${Number(h.id)};`),'cancelled');
 await api('siteA_team_lead',`/api/v1/duty/handovers/${h.id}/confirm`,{},409);checks.push('takeover transfers active/review events and tasks; cancels old handover');
 const cancelHistory=await api('admin','/api/v1/duty/handovers');assert.ok(cancelHistory.find(x=>x.id===h.id).audit.reason.includes('接管'));checks.push('cancellation audit retained');
 h=await api('admin','/api/v1/duty/handovers',{toUserId:'109'});await api('siteA_duty',`/api/v1/duty/handovers/${h.id}/confirm`,{});
 h=await api('siteA_duty','/api/v1/duty/handovers',{toUserId:'1'});
 await api('siteA_duty',`/api/v1/duty/handovers/${h.id}/cancel`,{reason:'QA sender cancel'});checks.push('non-admin initiator can cancel');
 h=await api('siteA_duty','/api/v1/duty/handovers',{toUserId:'1'});
 const raw=async(name,path,body)=>(await(await fetch(base+path,{method:'POST',headers:{Authorization:'Bearer '+tokens[name],'X-Site-Id':String(site),'Content-Type':'application/json'},body:JSON.stringify(body)})).json()).code;
 const results=await Promise.all([raw('siteA_duty',`/api/v1/duty/handovers/${h.id}/cancel`,{reason:'QA race'}),raw('admin',`/api/v1/duty/handovers/${h.id}/confirm`,{})]);
 assert.deepEqual(results.sort(),[200,409]);
 assert.equal(sql(`SELECT COUNT(*) FROM wear_duty_shift WHERE site_id=${site} AND ended_at IS NULL;`),'1');checks.push('concurrent cancel/confirm one winner and one active shift');
 const paged=await api('admin','/api/v1/duty/shifts?current=2&size=1');assert.equal(paged.records.length,1);assert.ok(paged.total>=4);checks.push('paginated ledger');
 await writeFile('C:/melhat-runtime/duty-api-results.json',JSON.stringify({checks,passed:checks.length,temporarySite:site},null,2));console.log(JSON.stringify({passed:checks.length,checks},null,2));
} finally {
 if(site && sql(`SELECT site_code FROM wear_site WHERE id=${site};`)===code) {
  sql(`DELETE a FROM wear_work_task_action a JOIN wear_work_task t ON t.id=a.task_id WHERE t.site_id=${site}; DELETE FROM wear_work_task WHERE site_id=${site}; DELETE FROM wear_safety_event WHERE site_id=${site}; DELETE a FROM wear_duty_handover_audit a JOIN wear_duty_handover h ON h.id=a.handover_id WHERE h.site_id=${site}; DELETE FROM wear_duty_handover WHERE site_id=${site}; DELETE FROM wear_duty_shift WHERE site_id=${site}; DELETE FROM wear_duty_station WHERE site_id=${site}; DELETE FROM wear_site_account WHERE site_id=${site}; DELETE FROM wear_site WHERE id=${site};`);
  console.log('Temporary test site and its records removed.');
 }
}
