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

test('real Caddy and paired gateway containers distribute, fail closed and drain without replaying writes',{timeout:120000},async t=>{
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
  const gateways={};
  for(const kind of ['helmet','belt'])for(const node of ['a','b']) {
    const name=`${kind}-${node}`;
    gateways[name]=start(name,['--mount',`type=bind,src=${join(root,name+'.json')},dst=/run/gateway.json,readonly`,image,kind,'/run/gateway.json']);
  }
  const ingressArgs=['-p','127.0.0.1::80','-e','CADDY_SITE=http://:80',
    '--mount',`type=bind,src=${join(deployment,'Caddyfile')},dst=/etc/caddy/Caddyfile,readonly`,
    '--mount',`type=bind,src=${join(root,'Caddy.devices')},dst=/etc/caddy/Caddy.devices,readonly`,caddy];
  let ingress=start('ingress',ingressArgs);
  let port=docker('port',ingress,'80/tcp').split(':').at(-1),origin=`http://127.0.0.1:${port}`;
  await until(async()=>(await fetch(origin+'/node')).ok);
  const nodes=new Set();for(let i=0;i<8;i++)nodes.add((await(await fetch(origin+'/node')).json()).node);
  assert.deepEqual([...nodes].sort(),['a','b']);
  for(const path of ['/internal/cluster/ready','/internal/gateway/drain','/druid/','/wsHat','/api/index.php'])assert.equal((await fetch(origin+path)).status,404);
  for(let i=0;i<4;i++)assert.equal((await fetch(origin+'/fail-write',{method:'POST',body:'once'})).status,503);
  function inContainer(name,code){return docker('exec',name,'node','-e',code);}
  let writes=0;for(const name of Object.values(backend))writes+=Number(inContainer(name,"fetch('http://127.0.0.1:18084/test/counts').then(r=>r.json()).then(r=>console.log(r.writes))"));
  assert.equal(writes,4,'failed writes must have exactly one upstream request each');
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
  for(let i=0;i<4;i++)assert.equal((await(await fetch(origin+'/node')).json()).node,'a');
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
  writeFileSync(join(root,'result.json'),JSON.stringify({passed:true,backend:'test-only HTTP/WS stand-in',gateways:'real container image',ingress:'real Caddy 2.10.2',failedWrites:4,observedWrites:writes,drainingNode:draining,httpDistribution:[...nodes],ingressGenerationRecreated:true,fullApplicationAcceptance:false},null,2));
});
