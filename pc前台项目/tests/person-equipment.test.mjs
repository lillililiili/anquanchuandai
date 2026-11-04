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
test('belt-only people have location but no personnel voice or camera capability',()=>{
  const f=fixture('B'); assert.equal(personFeature(f.db,'P1','video').supported,false);
  assert.equal(personFeature(f.db,'P1','location').available,true);
  assert.equal(personFeature(f.db,'P1','voice').available,false);
  assert.equal(personFeature(f.db,'P1','voice').supported,false);
  assert.match(personFeature(f.db,'P1','voice').reason,/未领用.*安全帽/);
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

function readyVoice() {
  const f=fixture();
  const live={supported:true,verified:false,available:true,integrationStatus:'CONNECTED',reason:''};
  Object.assign(f.device,{communicationProtocol:'SIP',sipRegistered:true,capabilities:{actions:['intercom']}});
  f.device.featureStates.voice={...live};
  f.db.state.personEquipmentContext.P1.features.voice={...live,personId:'P1',deviceId:'D1',assignmentId:'A1',assignmentVersion:1};
  f.db.state.bindings=[{personId:'P1',deviceId:'D1',assignmentId:'A1',assignmentVersion:1,end:null}];
  return f;
}
test('operational assigned helmet voice is enabled without manufacturing acceptance evidence',()=>{
  const f=readyVoice(), before=JSON.stringify(f.device.featureStates.voice);
  const result=personFeature(f.db,'P1','voice');
  assert.equal(result.available,true);assert.equal(result.verified,false);assert.equal(result.reason,'');
  assert.equal(JSON.stringify(f.device.featureStates.voice),before);
});
test('voice still blocks no helmet, stale assignment, offline device and server denial',()=>{
  const cases=[
    f=>f.unassign(),
    f=>{f.device.type='W';},
    f=>{f.device.online=false;},
    f=>{f.device.sourceTime='2020-01-01T00:00:00Z';},
    f=>{f.device.communicationProtocol='AGORA';},
    f=>{f.device.sipRegistered=false;},
    f=>{delete f.device.sipRegistered;},
    f=>{f.db.state.bindings[0].assignmentVersion=2;},
    f=>{f.db.state.bindings.push({...f.db.state.bindings[0],personId:'P2'});},
    f=>{f.db.state.personEquipmentContext.P1.features.voice.available=false;f.db.state.personEquipmentContext.P1.features.voice.reason='无操作权限';},
    f=>{f.device.featureStates.voice.available=false;},
    f=>{f.device.featureStates.voice.integrationStatus='NOT_CONNECTED';},
    f=>{f.person.active=false;},
  ];
  for(const change of cases){const f=readyVoice();change(f);assert.equal(personFeature(f.db,'P1','voice').available,false);}
});

test('legacy server capability reasons become actionable messages without enabling a denied command', () => {
  const f=readyVoice();
  for (const reason of ['待联调', '尚未接入', '尚未部署']) {
    Object.assign(f.db.state.personEquipmentContext.P1.features.voice, {available:false, reason});
    const result=personFeature(f.db,'P1','voice');
    assert.equal(result.available,false);
    assert.doesNotMatch(result.reason,/待联调|未接入|未部署/);
    assert.match(result.reason,/检查/);
  }
  f.device.online=false;f.device.communicationProtocol='';
  assert.equal(personFeature(f.db,'P1','voice').reason,'设备离线');
});
