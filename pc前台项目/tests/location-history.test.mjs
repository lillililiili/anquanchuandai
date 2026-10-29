import test from 'node:test';
import assert from 'node:assert/strict';
import { beijingDate, eventLocation, mapLocation, prepareTracks, toMapCoordinates, trackRange, trackSegments } from '../src/lib/location.js';
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
