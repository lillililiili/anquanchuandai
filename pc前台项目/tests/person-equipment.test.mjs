import test from 'node:test';
import assert from 'node:assert/strict';
import { personFeature, videoPeople, operationContext } from '../src/lib/person-equipment.js';
const accepted={supported:true,verified:true,available:true,reason:''};
function fixture(type='H') {
  const device={id:'D1',type,active:true,online:true,source:type==='H'?'DIRECT_HELMET':'DIRECT_BELT',freshness:'CURRENT',sourceTime:new Date().toISOString(),featureStates:{video:type==='H'?accepted:{supported:false},location:accepted,voice:{supported:true,verified:false,available:false,reason:type==='B'?'待接入':'待联调'}}};
  const person={id:'P1',active:true};let assigned=true;
  const context={...accepted,deviceId:'D1',assignmentId:'A1',assignmentVersion:1};
  const db={person:()=>person,device:()=>device,currentDevices:()=>assigned?[device]:[],state:{personEquipmentContext:{P1:{features:{video:context,location:context,voice:{...context,...device.featureStates.voice}}}}}};
  return {db,device,person,unassign:()=>{assigned=false;}};
}
test('belt-only people have location and pending voice but never camera capability',()=>{
  const f=fixture('B'); assert.equal(personFeature(f.db,'P1','video').supported,false);
  assert.equal(personFeature(f.db,'P1','location').available,true);
  assert.equal(personFeature(f.db,'P1','voice').available,false);
  assert.equal(personFeature(f.db,'P1','voice').reason,'待接入');
  assert.deepEqual(videoPeople(f.db,[f.person]),[]);
});
test('offline assigned helmet remains a supported video candidate, with actions disabled',()=>{
  const f=fixture();f.device.online=false;
  assert.equal(personFeature(f.db,'P1','video').supported,true);
  assert.equal(personFeature(f.db,'P1','video').available,false);
  assert.equal(videoPeople(f.db,[f.person]).length,1);
});
test('returned equipment cannot be operated through a stale server context',()=>{
  const f=fixture();f.unassign();assert.equal(personFeature(f.db,'P1','video').supported,false);
  assert.throws(()=>operationContext(personFeature(f.db,'P1','video')),/领用/);
});
test('missing context fails closed and stale telemetry never enables a live action',()=>{
  const f=fixture();delete f.db.state.personEquipmentContext;
  assert.equal(personFeature(f.db,'P1','video').available,false);
  assert.equal(personFeature(f.db,'P1','video').supported,true);
  const g=fixture();g.device.sourceTime='2020-01-01T00:00:00Z';assert.equal(personFeature(g.db,'P1','video').available,false);
});
test('operation captures only identity/version, not device telemetry',()=>{
  const f=fixture();assert.deepEqual(operationContext(personFeature(f.db,'P1','video')),{personId:'P1',deviceId:'D1',assignmentId:'A1',assignmentVersion:1});
});
test('server permission revocation disables an online accepted device without hiding its capability',()=>{
  const f=fixture();
  assert.equal(personFeature(f.db,'P1','video').available,true);
  Object.assign(f.db.state.personEquipmentContext.P1.features.video,{available:false,reason:'无操作权限'});
  const denied=personFeature(f.db,'P1','video');
  assert.equal(denied.supported,true);
  assert.equal(denied.verified,true);
  assert.equal(denied.available,false,'device online/acceptance cannot override the server denial');
  assert.equal(denied.reason,'无操作权限');
  assert.deepEqual(videoPeople(f.db,[f.person]),[f.person],'keep the channel status visible after permission revocation');
});
