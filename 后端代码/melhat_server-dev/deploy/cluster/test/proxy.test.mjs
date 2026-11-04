import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdtempSync,writeFileSync,mkdirSync,renameSync} from 'node:fs';
import {resolve,dirname,join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {randomBytes} from 'node:crypto';
import {once} from 'node:events';
import {createRequire} from 'node:module';
import {setTimeout as delay} from 'node:timers/promises';
import {renderConfigs} from '../../../local-dev/protocol-cluster/render-config.mjs';
const require=createRequire(new URL('../../../local-dev/protocol-cluster/package.json',import.meta.url));
const WebSocket=require('ws');
const here=dirname(fileURLToPath(import.meta.url)),deployment=resolve(here,'..');
const image=process.env.CLUSTER_GATEWAY_TEST_IMAGE??'wearable-gateway:cluster-lab';
const caddy='caddy:2.10.2-alpine@sha256:4c6e91c6ed0e2fa03efd5b44747b625fec79bc9cd06ac5235a779726618e530d';
function docker(...args){return execFileSync('docker',args,{encoding:'utf8',timeout:60000,windowsHide:true,stdio:['ignore','pipe','pipe']}).trim();}
async function until(check){for(let i=0;i<80;i++){try{if(await check())return;}catch{}await delay(100);}throw Error('Proxy condition did not become true');}

test('complete real entry preserves API/media routes and paired gateway failover without replaying writes',{timeout:180000},async t=>{
  const evidence=resolve(deployment,'evidence');mkdirSync(evidence,{recursive:true});
  const root=mkdtempSync(join(evidence,'proxy-')),suffix=randomBytes(4).toString('hex');
  const network=`wearable-proxy-${suffix}`,containers=[],prefix=`wearable-proxy-${suffix}`;
  const secret=()=>randomBytes(32).toString('base64url');
  const inventory={publicOrigin:'https://wearable.example.com',adminToken:secret(),drainTimeoutMillis:1000,
    helmets:[{deviceId:'900000000000001',pathToken:secret()}],belts:[{deviceId:'900000000000002',pathToken:secret()}]};
  for(const [name,body] of Object.entries(renderConfigs(inventory)))writeFileSync(join(root,name),body);
  docker('network','create',network);
  t.after(()=>{for(const name of containers.reverse()){try{docker('rm','-f',name);}catch{}}try{docker('network','rm',network);}catch{}});
  function start(alias,args){const name=`${prefix}-${alias}`;containers.push(name);docker('run','-d','--name',name,'--network',network,'--network-alias',alias,'--memory','96m','--cpus','0.5',...args);return name;}
  const backend={};
  for(const node of ['a','b'])backend[node]=start(`app-${node}`,['--mount',`type=bind,src=${join(here,'proxy-fixture.mjs')},dst=/opt/wearable/proxy-fixture.mjs,readonly`,'-e',`FIXTURE_NODE=${node}`,'--entrypoint','node',image,'/opt/wearable/proxy-fixture.mjs']);
  start('backend',['--mount',`type=bind,src=${join(deployment,'Caddy.backend')},dst=/etc/caddy/Caddyfile,readonly`,caddy]);
  for(const kind of ['wear','fuda'])start(`${kind}-api`,['--entrypoint','node',image,'/opt/wearable/protocol-cluster/api-cli.mjs',kind]);
  start('entry-dependency',['--mount',`type=bind,src=${join(here,'entry-dependency-fixture.mjs')},dst=/opt/wearable/entry-fixture.mjs,readonly`,'--entrypoint','node',image,'/opt/wearable/entry-fixture.mjs']);
  const gateways={};
  for(const kind of ['helmet','belt'])for(const node of ['a','b']) {
    const name=`${kind}-${node}`;
    gateways[name]=start(name,['--mount',`type=bind,src=${join(root,name+'.json')},dst=/run/gateway.json,readonly`,image,kind,'/run/gateway.json']);
  }
  const ingressArgs=['-p','127.0.0.1::80','-e','CADDY_SITE=http://:80',
    '-e','PC_STATIC_UPSTREAM=entry-dependency:18084','-e','MEDIA_UPSTREAM=entry-dependency:18084','-e','SIP_UPSTREAM=entry-dependency:18084',
    '--mount',`type=bind,src=${join(deployment,'Caddyfile')},dst=/etc/caddy/Caddyfile,readonly`,
    '--mount',`type=bind,src=${join(root,'Caddy.devices')},dst=/etc/caddy/Caddy.devices,readonly`,caddy];
  let ingress=start('ingress',ingressArgs);
  let port=docker('port',ingress,'80/tcp').split(':').at(-1),origin=`http://127.0.0.1:${port}`;
  await until(async()=>(await fetch(origin+'/api/guardian/v1/snapshot')).ok);
  const nodes=new Set();for(let i=0;i<8;i++)nodes.add((await(await fetch(origin+'/api/guardian/v1/snapshot')).json()).node);
  assert.deepEqual([...nodes].sort(),['a','b']);
  for(const path of ['/internal/cluster/ready','/internal/gateway/drain','/druid/','/wsHat','/api/index.php','/api/melhat/anything','/openapi/other','/wear-api/other','/helmet-media/internal','/monitor/job/list','/test/anything'])assert.equal((await fetch(origin+path)).status,404);
  for(let i=0;i<4;i++)assert.equal((await fetch(origin+'/api/guardian/v1/business/commands',{method:'POST',body:'once'})).status,503);
  function inContainer(name,code){return docker('exec',name,'node','-e',code);}
  let writes=0;for(const name of Object.values(backend))writes+=Number(inContainer(name,"fetch('http://127.0.0.1:18084/test/counts').then(r=>r.json()).then(r=>console.log(r.writes))"));
  assert.equal(writes,4,'failed writes must have exactly one upstream request each');
  const mobile='/wear-api/api/guardian/v1',token=secret();
  const logged=await(await fetch(origin+mobile+'/mobile/login',{method:'POST',body:'{"login":"isolated"}',headers:{'Content-Type':'application/json','Authorization':'strip','Cookie':'strip','X-Real-IP':'1.2.3.4'}})).json();
  assert.equal(logged.path,'/api/guardian/v1/mobile/login');assert.equal(logged.headers.authorization,undefined);assert.equal(logged.headers.cookie,undefined);
  const mobileNodes=new Set();
  for(let i=0;i<8;i++)mobileNodes.add((await(await fetch(origin+mobile+'/mobile/context',{headers:{'X-Wearable-Token':token}})).json()).node);
  assert.deepEqual([...mobileNodes].sort(),['a','b']);
  assert.equal((await fetch(origin+mobile+'/snapshot',{headers:{'X-Wearable-Token':token}})).status,404,'PC snapshot must not enter mobile whitelist');
  assert.equal((await fetch(origin+mobile+'/mobile/context?unsupported=yes',{headers:{'X-Wearable-Token':token}})).status,400);
  assert.equal((await fetch(origin+mobile+'/mobile/context')).status,401);
  assert.equal((await(await fetch(origin+'/api/admin/v1/fixture')).json()).code,0);
  for(let i=1;i<12;i++)assert.equal((await fetch(origin+mobile+'/mobile/login',{method:'POST',headers:{'X-Real-IP':`9.9.9.${i}`},body:'{}'})).status,200);
  assert.equal((await fetch(origin+mobile+'/mobile/login',{method:'POST',headers:{'X-Real-IP':'8.8.8.8'},body:'{}'})).status,429,'spoofed source cannot reset login limiter');
  for(const path of ['/api/guardian/v1/mobile/login','/api/guardian/v1/login'])assert.equal((await fetch(origin+path,{method:'POST',headers:{'X-Real-IP':'4.4.4.4'},body:'{}'})).status,429,'root PC aliases cannot bypass the same login limiter');
  assert.equal((await fetch(origin+'/api/guardian/v1/mobile/context')).status,401);
  assert.equal((await fetch(origin+'/api/guardian/v1/mobile/context?unsupported=yes',{headers:{'X-Wearable-Token':token}})).status,400);
  assert.equal((await fetch(origin+'/api/guardian/v1/snapshot',{method:'POST',body:'{}'})).status,404);
  assert.equal((await fetch(origin+'/api/guardian/v1/business/commands')).status,404);
  assert.equal((await fetch(origin+mobile+'/devices/fixture/commands',{method:'POST',headers:{'X-Wearable-Token':token},body:'x'.repeat(128*1024+1)})).status,413);
  const signed='{ "value":9007199254740993, "name":"中文 😀" }';
  const fudaHeaders={'Content-Type':'application/json','X-App-Id':'isolated','X-Timestamp':'1','X-Nonce':'fixture','X-Signature':'fixture','Authorization':'strip','Cookie':'strip','X-Wearable-Token':token};
  for(const kind of ['positions','statuses','alarms']){
    const path=`/openapi/wearables/v2/${kind}/query`,r=await fetch(origin+path,{method:'POST',headers:fudaHeaders,body:signed});assert.equal(r.status,200);
    const body=await r.json();assert.equal(body.path,path);assert.equal(body.body,signed);assert.equal(body.headers['x-app-id'],'isolated');assert.equal(body.headers.authorization,undefined);assert.equal(body.headers['x-wearable-token'],undefined);
    assert.equal((await fetch(origin+path)).status,404);
  }
  assert.equal((await fetch(origin+'/openapi/wearables/v2/positions/query?extra=1',{method:'POST',headers:fudaHeaders,body:signed})).status,404);
  assert.equal((await fetch(origin+'/openapi/wearables/v2/positions/query',{method:'POST',headers:fudaHeaders,body:'x'.repeat(65537)})).status,413);
  const mediaPath='/helmet-media/control/v1/fixture?z=1&key=a%2Fb';
  const media=await(await fetch(origin+mediaPath,{method:'POST',headers:{'X-Media-Signature':'unchanged','Origin':'http://lab-pc'},body:signed})).json();
  assert.equal(media.path,mediaPath);assert.equal(media.body,signed);assert.equal(media.headers['x-media-signature'],'unchanged');
  for(const method of ['GET','HEAD']){const response=await fetch(origin+'/helmet-media/files/fixture?ticket=isolated',{method,headers:{Range:'bytes=0-3'}});assert.equal(response.status,206);assert.equal(response.headers.get('content-range'),'bytes 0-3/8');assert.equal(await response.text(),method==='GET'?'abcd':'');}
  for(const path of ['/helmet-media/whep/fixture?ticket=isolated','/helmet-media/hls/fixture.m3u8?ticket=isolated'])assert.equal((await(await fetch(origin+path)).json()).path,path);
  const sip=new WebSocket(origin.replace('http:','ws:')+'/helmet-media/sip');await once(sip,'open');const sipReply=once(sip,'message');sip.send('isolated');assert.equal(JSON.parse((await sipReply)[0]).path,'/helmet-media/sip');sip.close();
  assert.equal((await(await fetch(origin+'/existing-pc-route')).json()).dependency,true,'PC fallback stays outside Spring');
  const device=inventory.helmets[0];
  async function connect(){const ws=new WebSocket(origin.replace('http:','ws:')+`/${device.pathToken}/wsHat`);ws.on('error',()=>{});await once(ws,'open');const message=once(ws,'message');ws.send(JSON.stringify({act:'ca_login',device_id:device.deviceId}));const [raw]=await message;return {ws,node:JSON.parse(raw).node};}
  const sessions=[];t.after(()=>{for(const s of sessions)s.ws.terminate();});
  await delay(2200); // First active health round includes all four paired gateways.
  for(let i=0;i<4;i++)sessions.push(await connect());
  assert.deepEqual([...new Set(sessions.map(s=>s.node))].sort(),['a','b']);
  const draining=sessions[0].node,closed=once(sessions[0].ws,'close');
  const result=inContainer(gateways[`helmet-${draining}`],"const c=require('/run/gateway.json');fetch('http://127.0.0.1:8080/internal/gateway/drain',{method:'POST',headers:{'X-Cluster-Admin-Token':c.adminToken}}).then(r=>console.log(r.status))");
  assert.equal(result,'202');await closed;await delay(2300);
  for(let i=0;i<4;i++){const s=await connect();sessions.push(s);assert.notEqual(s.node,draining);}
  inContainer(backend.b,"fetch('http://127.0.0.1:18084/test/ready/false').then(r=>r.text())");await delay(2300);
  for(let i=0;i<4;i++)assert.equal((await(await fetch(origin+'/api/guardian/v1/snapshot')).json()).node,'a');
  // Atomic source replacement cannot hot-update a single-file bind or parsed Caddy config.
  const next={...inventory,helmets:[{...device,pathToken:secret()}]};
  for(const [name,body] of Object.entries(renderConfigs(next))){writeFileSync(join(root,name+'.new'),body);renameSync(join(root,name+'.new'),join(root,name));}
  const newPath=`/${next.helmets[0].pathToken}/api/index.php?ctl=config&act=get_config&device_id=${device.deviceId}`;
  const oldResponse=await(await fetch(origin+newPath)).json();assert.notEqual(oldResponse.status,true);
  // A complete maintenance-window recreation includes ingress as well as every gateway.
  for(const name of Object.values(gateways))docker('rm','-f',name);docker('rm','-f',ingress);
  for(const kind of ['helmet','belt'])for(const node of ['a','b']) {
    const name=`${kind}-${node}`;gateways[name]=start(name,['--mount',`type=bind,src=${join(root,name+'.json')},dst=/run/gateway.json,readonly`,image,kind,'/run/gateway.json']);
  }
  ingress=start('ingress',ingressArgs);port=docker('port',ingress,'80/tcp').split(':').at(-1);origin=`http://127.0.0.1:${port}`;
  await until(async()=>{const r=await fetch(origin+newPath);return r.ok&&(await r.json()).status===true;});
  writeFileSync(join(root,'result.json'),JSON.stringify({passed:true,backend:'test-only HTTP/WS stand-in',media:'transport-only stand-in; authentication/playback not claimed',gateways:'real protocol/wear/fuda image',ingress:'real Caddy 2.10.2 and private router',failedWrites:4,observedWrites:writes,drainingNode:draining,httpDistribution:[...nodes],mobileDistribution:[...mobileNodes],mobilePrefixAndRateLimit:true,fudaRawBytesAndWhitelist:true,mediaRangeAndSipRouting:true,ingressGenerationRecreated:true,fullApplicationAcceptance:false},null,2));
});
