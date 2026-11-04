import test from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {renderConfigs,requirePrivateDirectory,publishGeneration} from '../render-config.mjs';
import {mkdtemp,chmod,rm,readFile,access} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
const secret=()=>randomBytes(32).toString('base64url');
function inventory(){return {publicOrigin:'https://wearable.example.com',adminToken:secret(),
  helmets:[{deviceId:'900000000000001',pathToken:secret()}],belts:[{deviceId:'900000000000002',pathToken:secret()}]};}
test('paired nodes retain identical device secrets and use their own backend',()=>{
  const input=inventory(),files=renderConfigs(input);
  assert.equal(Object.keys(files).length,5);
  for(const kind of ['helmet','belt'])for(const node of ['a','b']) {
    const config=JSON.parse(files[`${kind}-${node}.json`]);
    assert.equal(config.upstreamOrigin,`http://app-${node}:18084`);
    assert.deepEqual(config.devices,input[kind==='helmet'?'helmets':'belts']);
    assert.equal(config.adminToken,input.adminToken);
  }
  assert.ok(files['Caddy.devices'].includes(`/${input.belts[0].pathToken.slice(0,24)}/wsHat`));
  assert.ok(files['Caddy.devices'].includes('reverse_proxy helmet-a:8080 helmet-b:8080'));
});
test('cross-protocol duplicate or abbreviated secrets are rejected before any output',()=>{
  const input=inventory();input.belts[0].pathToken=input.helmets[0].pathToken;
  assert.throws(()=>renderConfigs(input));
});
test('existing publicly accessible output directories are rejected on POSIX',{skip:process.platform==='win32'},async t=>{
  const root=await mkdtemp(join(tmpdir(),'wearable-config-'));t.after(()=>rm(root,{recursive:true,force:true}));
  await chmod(root,0o755);await assert.rejects(()=>requirePrivateDirectory(root));
  await chmod(root,0o700);await requirePrivateDirectory(root);
});
test('interruption between replacements leaves a blocking marker and never a valid mixed generation',async t=>{
  const root=await mkdtemp(join(tmpdir(),'wearable-generation-'));t.after(()=>rm(root,{recursive:true,force:true}));
  const input=inventory();await publishGeneration(root,renderConfigs(input));
  const oldManifest=await readFile(join(root,'gateway-manifest.json'),'utf8');
  const next={...input,adminToken:secret()};let published=0;
  await assert.rejects(()=>publishGeneration(root,renderConfigs(next),true,()=>{if(++published===2)throw Error('injected I/O failure');}));
  assert.equal(published,2);await access(join(root,'.gateway-config.incomplete'));
  assert.equal(await readFile(join(root,'gateway-manifest.json'),'utf8'),oldManifest);
  assert.notEqual(JSON.parse(await readFile(join(root,'helmet-a.json'),'utf8')).adminToken,
    JSON.parse(await readFile(join(root,'belt-b.json'),'utf8')).adminToken);
  await assert.rejects(()=>publishGeneration(root,renderConfigs(next),true));
});
