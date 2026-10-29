import test from 'node:test';
import assert from 'node:assert/strict';
import { createLiveViewing } from '../src/lib/live-viewing.js';
const context={personId:'P1',deviceId:'D1',assignmentId:'A1',assignmentVersion:1};
function fixture(command) {
  const calls=[],timers=new Map();let next=0;
  const api={async command(...args){calls.push(args);return command?command(...args):{status:'sent'};},async live(id,ctx){calls.push(['live',ctx]);return {live:{protocol:'WHEP',url:'https://media.test/a',hlsUrl:'https://media.test/a.m3u8'}};}};
  const manager=createLiveViewing({api,makeId:()=>`key-${++next}`,schedule:(fn,delay)=>{const id=++next;timers.set(id,{fn,delay});return id;},cancel:id=>timers.delete(id)});
  return {manager,calls,async release(){for(const [id,t] of [...timers])if(t.delay===750){timers.delete(id);await t.fn();}}};
}
test('mounting never starts a stream; explicit open starts once and chooses HLS',async()=>{
  const f=fixture();let state;const view=f.manager.watch(context,s=>{state=s;});assert.equal(f.calls.length,0);
  await view.open();assert.equal(f.calls.filter(c=>c[1]==='start_video').length,1);assert.equal(state.live.protocol,'HLS');
  assert.equal(state.live.url,'https://media.test/a.m3u8');view.dispose();await f.release();
});
test('closing one consumer never stops the other; last release stops only its viewer lease',async()=>{
  const f=fixture();const a=f.manager.watch(context,()=>{}),b=f.manager.watch(context,()=>{});
  await Promise.all([a.open(),b.open()]);assert.equal(f.calls.filter(c=>c[1]==='start_video').length,1);
  a.dispose();await f.release();assert.equal(f.calls.filter(c=>c[1]==='stop_video').length,0);
  b.dispose();await f.release();const start=f.calls.find(c=>c[1]==='start_video'),stop=f.calls.find(c=>c[1]==='stop_video');
  assert.equal(start[5].viewerSessionId,stop[5].viewerSessionId);assert.equal(stop[5].assignmentId,'A1');
});
test('a stopped view can be opened again with a distinct lease',async()=>{
  const f=fixture();const a=f.manager.watch(context,()=>{});await a.open();a.close();await f.release();await a.open();
  const starts=f.calls.filter(c=>c[1]==='start_video');assert.equal(starts.length,2);assert.notEqual(starts[0][5].viewerSessionId,starts[1][5].viewerSessionId);
  a.dispose();await f.release();
});
test('a returned/reassigned device uses different leases and original cleanup context',async()=>{
  const f=fixture();const a=f.manager.watch(context,()=>{});await a.open();a.dispose();
  const b=f.manager.watch({...context,personId:'P2',assignmentId:'A2',assignmentVersion:2},()=>{});await b.open();await f.release();
  assert.equal(f.calls.find(c=>c[1]==='stop_video')[5].personId,'P1');b.dispose();await f.release();
});
test('uncertain start retries with the same idempotency key',async()=>{
  let attempt=0;const f=fixture(async(id,action)=>{if(action==='start_video'&&++attempt===1)throw Error('network');return {status:'sent'};});
  const a=f.manager.watch(context,()=>{});await a.open();await a.open();
  const starts=f.calls.filter(c=>c[1]==='start_video');assert.equal(starts[0][3],starts[1][3]);a.dispose();await f.release();
});
