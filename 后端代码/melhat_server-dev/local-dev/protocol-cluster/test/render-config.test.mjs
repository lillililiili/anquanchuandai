import test from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {renderConfigs} from '../render-config.mjs';
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
