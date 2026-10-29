import test from 'node:test';
import assert from 'node:assert/strict';
import { featureState, actionFeatureState } from '../../shared/device-features.mjs';
import { projectSingleSimulatedWatch } from '../../shared/simulated-watch.mjs';
import { createBusinessCommands } from '../src/lib/business-commands.js';
import { createStore, seed } from '../src/mock/data.js';

test('hardware support, acceptance and availability remain separate', () => {
  const d = { featureStates: { video: { supported: true, verified: true, available: true }, photo: { supported: true, verified: false, available: true }, voice: { supported: false, verified: true, available: true } } };
  assert.equal(actionFeatureState(d, 'start_video').available, true);
  assert.deepEqual(actionFeatureState(d, 'take_photo'), { supported: true, verified: false, available: false, reason: '待联调' });
  assert.equal(featureState(d, 'voice').supported, false);
  assert.equal(featureState(d, 'voice').available, false);
  assert.equal(actionFeatureState({ capabilities: ['intercom'] }, 'intercom').available, false);
});
test('one switch removes simulated devices, bindings and vitals but preserves real evidence', () => {
  const s = { businessConfig: { simulatedWatchVisible: false }, devices: [{ id: 'RL-W001', type: 'W', station: 'S1', source: 'DEMO_WATCH' }, { id: 'real', type: 'H', source: 'DIRECT_HELMET' }], bindings: [{ deviceId: 'RL-W001', personId: 'P1' }], vitals: [{ deviceId: 'RL-W001', personId: 'P1', source: 'DEMO_WATCH' }], events: [{ id: 'sample', deviceId: 'RL-W001', demo: true }, { id: 'real', deviceId: 'RL-W001', source: 'DEVICE' }] };
  const next = projectSingleSimulatedWatch(s);
  assert.deepEqual(next.devices.map(x=>x.id), ['real']); assert.equal(next.bindings.length, 0); assert.equal(next.vitals.length, 0); assert.deepEqual(next.events.map(x=>x.id), ['real']); assert.equal(s.devices.length, 2);
});
test('version retirement clears business cache and keeps login storage untouched', () => {
  const data = new Map([['rolling-native-v1', JSON.stringify(seed())], ['rolling-session', 'login']]);
  const store = createStore({ getItem:k=>data.get(k), setItem:(k,v)=>data.set(k,v), removeItem:k=>data.delete(k) }, { requiredDataVersion:'wearable-clean-v1' });
  assert.equal(store.state.devices.length, 0); assert.equal(data.has('rolling-native-v1'), false); assert.equal(data.get('rolling-session'), 'login');
});
test('commands submit only intent, preserve idempotency on uncertain result and apply server state', () => {
  let attempts=0, state={seq:3}; const requests=[];
  const command=createBusinessCommands({ current:()=>state, replace:s=>(state=s,true), makeId:()=> 'same-key', request:(url,body)=>{requests.push({url,body});if(++attempts===1)throw Error('timeout');return{state:{seq:4},result:{id:'F1'}};} });
  assert.throws(()=>command('fences.toggle',{id:'F1',enabled:true}),/timeout/);
  assert.deepEqual(command('fences.toggle',{id:'F1',enabled:true}),{id:'F1'});
  assert.deepEqual(requests[0].body, {operationId:'same-key',type:'fences.toggle',payload:{id:'F1',enabled:true},expectedSeq:3});
  assert.equal(requests[1].body.operationId,requests[0].body.operationId); assert.equal(state.seq,4);
});
