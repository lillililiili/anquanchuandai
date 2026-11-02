import test from 'node:test';
import assert from 'node:assert/strict';
import { beijingDate, eventLocation, mapLocation, prepareTracks, toMapCoordinates, trackRange, trackSegments, trackTimestamp, trackBreakLabel, trackEvents, trackQueryContext } from '../src/lib/location.js';
import { createLocationApi } from '../src/lib/guardian-location.js';
import { createStore, seed } from '../src/mock/data.js';

const point = (minute, extra = {}) => ({ id: String(minute), latitude: 31.2, longitude: 121.4, coordinateSystem: 'GCJ02', locationQuality: 'valid', deviceId: 'H1', reportedAt: `2026-10-23T00:${String(minute).padStart(2,'0')}:00Z`, ...extra });

test('unknown or stale location never becomes a current map marker', () => {
  const current = point(0, { locationFreshness: 'CURRENT' });
  assert.deepEqual(mapLocation(current, { current: true, now: Date.parse(current.reportedAt) }), [121.4,31.2]);
  assert.equal(mapLocation({...current, coordinateSystem:'UNKNOWN'}), null);
  assert.equal(mapLocation({...current, locationQuality:'unknown'}), null);
  assert.equal(mapLocation({...current, longitude:null}), null);
  assert.equal(mapLocation(current, {current:true, now:Date.parse(current.reportedAt)+300001}), null);
  assert.deepEqual(toMapCoordinates({ longitude:-0.1, latitude:51.5, coordinateSystem:'WGS84'}),[-0.1,51.5]);
  const gcj = toMapCoordinates({ longitude:116.404, latitude:39.915, coordinateSystem:'WGS84'});
  assert.ok(Math.abs(gcj[0]-116.4102445)<0.00001 && Math.abs(gcj[1]-39.9164043)<0.00001);
});

test('history groups real gaps, invalid points and device changes without interpolation', () => {
  const points = prepareTracks([point(12), point(0), point(1), point(2,{locationQuality:'unknown'}), point(3), point(3), point(13,{deviceId:'H2'})]);
  assert.equal(points.length,5);
  assert.deepEqual(trackSegments(points).map(group=>group.map(row=>row.time)),[['08:00:00','08:01:00'],['08:03:00'],['08:12:00'],['08:13:00']]);
});

test('an invalid belt fix cannot split the same persons uninterrupted valid helmet track',()=>{
  const common={personId:'P1',bindingId:'helmet-assignment'};
  const rows=[point(0,common),point(1,{id:'belt-invalid-1',deviceId:'B1',personId:'P1',bindingId:'belt-assignment',coordinateSystem:'UNKNOWN'}),
    point(1,common),point(2,{id:'belt-invalid-2',deviceId:'B1',personId:'P1',bindingId:'belt-assignment',locationQuality:'unknown'}),
    point(2,common),point(3,{...common,locationQuality:'unknown'}),point(4,common)];
  const result=prepareTracks(rows);
  assert.deepEqual(trackSegments(result).map(group=>group.map(row=>row.id)),[['0','1','2'],['4']]);
  assert.equal(result.at(-1).gapReason,'INVALID_LOCATION','an actual same-helmet loss still splits its track');
  const changed=prepareTracks([point(0,common),point(1,{personId:'P1',deviceId:'B1',bindingId:'belt-assignment'}),point(2,common)]);
  assert.deepEqual(changed.slice(1).map(row=>row.gapReason),['DEVICE_CHANGED','DEVICE_CHANGED']);
});

test('date range is Beijing time independently of browser timezone', () => {
  assert.equal(beijingDate(Date.parse('2026-10-22T17:00:00Z')),'2026-10-23');
  assert.deepEqual(trackRange('2026-10-23','00:00','23:59'),{from:'2026-10-22T16:00:00.000Z',to:'2026-10-23T15:59:59.999Z'});
  assert.throws(()=>trackRange('2026-02-30','00:00','23:59'));
  const event = eventLocation({locationLat:31.2,locationLng:121.4,coordinateSystem:'GCJ02',locationQuality:'valid'});
  assert.deepEqual(mapLocation(event),[121.4,31.2]);
});

test('history follows cursor and does not fabricate data on empty or failed responses', async () => {
  const calls=[];
  const api=createLocationApi(async url=>{calls.push(url); return {ok:true,json:async()=> calls.length===1 ? {rows:[point(0)],nextCursor:'next'} : {rows:[point(1)],nextCursor:null}}});
  const result=await api.history('P1','2026-10-23','00:00','23:59');
  assert.equal(result.points.length,2);
  assert.match(calls[1],/cursor=next/);
  const empty=await createLocationApi(async()=>({ok:true,json:async()=>({rows:[]})})).history('P1','2026-10-23','00:00','23:59');
  assert.deepEqual(empty.points,[]);
  await assert.rejects(()=>createLocationApi(async()=>({ok:false,json:async()=>({message:'没有权限'})})).history('P1','2026-10-23','00:00','23:59'),/没有权限/);
});

test('connected store never substitutes sample history for an empty device history',()=>{
  const store=createStore(null);store.replaceRemote(seed());store.setRemoteCommit(()=>{});
  assert.deepEqual(store.tracks('P1','2026-09-15','00:00','23:59'),[]);
});

test('device history queries stay independent from current person assignment',async()=>{
  let url;
  const api=createLocationApi(async value=>{url=value;return {ok:true,json:async()=>({rows:[point(0,{personId:null,deviceId:'belt'})]})};});
  const result=await api.history(null,'2026-10-23','00:00','23:59',{deviceId:'belt'});
  const query=new URL(url,'https://local.test').searchParams;
  assert.equal(query.get('deviceId'),'belt');assert.equal(query.has('personId'),false);
  assert.equal(result.points[0].personId,null);
});

test('same-device history separates people and return/reissue bindings without rewriting attribution',()=>{
  const rows=[point(0,{personId:'P1',bindingId:'A1'}),point(1,{personId:'P1',bindingId:'A1'}),
    point(2,{personId:'P1',bindingId:'A2'}),point(3,{personId:'P2',bindingId:'A3'}),point(4,{personId:null,bindingId:null})];
  const original=structuredClone(rows), result=prepareTracks(rows);
  assert.deepEqual(trackSegments(result).map(group=>group.length),[2,1,1,1]);
  assert.ok(result.slice(2).every(row=>row.gapReason==='ASSIGNMENT_CHANGED'));
  assert.equal(trackBreakLabel(result[2]),'历史领用关系变化');assert.deepEqual(rows,original);
  const boundary=prepareTracks([point(0,{assignmentId:'A1',assignmentVersion:1}),point(1,{assignmentId:'A1',assignmentVersion:2})]);
  assert.equal(boundary[1].gap,true);
});

test('history time ordering follows the declared collected or received basis and never invents missing capture time',()=>{
  const collected=point(4,{id:'offline',locationTimeBasis:'DEVICE_COLLECTED_AT',collectedAt:'2026-10-23T00:00:00Z',receivedAt:'2026-10-23T00:05:00Z'});
  const received=point(0,{id:'live',locationTimeBasis:'RECEIVED_AT',receivedAt:'2026-10-23T00:01:00Z',deviceReportedAt:'2026-10-23T00:00:30Z'});
  const result=prepareTracks([received,collected]);
  assert.deepEqual(result.map(row=>[row.id,row.time]),[['offline','08:00:00'],['live','08:01:00']]);
  assert.equal(result[1].collectedAt,undefined);assert.equal(result[0].reportedAt,collected.reportedAt);
  assert.equal(trackTimestamp({...received,locationTimeBasis:'UNKNOWN'}),'');
  assert.equal(prepareTracks([{...collected,collectedAt:null,reportedAt:null}]).length,0,'missing collected time cannot use receipt time');
});

test('person deep links override a cached device filter while the general tracks route retains it',()=>{
  const cached={mode:'device',deviceId:'B1',personId:'old-person',date:'2026-10-23',start:'08:00',end:'09:00'};
  assert.deepEqual(trackQueryContext(cached,'person-from-map'),{...cached,mode:'person',personId:'person-from-map',deviceId:''});
  assert.deepEqual(trackQueryContext(cached),cached);
  assert.equal(trackQueryContext(cached,'unknown-person').personId,'unknown-person','an invalid deep link must not silently select another person');
  assert.equal(cached.mode,'device','resolving a deep link does not mutate the caller cache before it is applied');
});

test('trajectory events use the queried owner or device and Beijing interval, including verified historical events',()=>{
  const base={personId:'P1',deviceId:'H1',date:'2026-10-23',time:'08:30:00',status:'已核验'};
  const rows=[{...base,id:'in'}, {...base,id:'prior',date:'2026-10-22'}, {...base,id:'late',time:'09:01:00'},
    {...base,id:'other',personId:'P2',deviceId:'B1'}, {...base,id:'no-date',date:''},
    {...base,id:'boundary',time:'09:00:59'}, {...base,id:'early',time:'08:00:00'}];
  const query={personId:'P1',date:'2026-10-23',start:'08:00',end:'09:00'};
  assert.deepEqual(trackEvents(rows,query).map(row=>row.id),['early','in','boundary']);
  assert.deepEqual(trackEvents(rows,{...query,personId:undefined,deviceId:'B1'}).map(row=>row.id),['other']);
});
