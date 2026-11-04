import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { parse, compileScript } from '@vue/compiler-sfc';
import * as Vue from 'vue';
import * as messages from '../src/lib/device-voice-messages.js';
import * as dateTime from '../src/lib/date-time.js';

const message = {id:'voice-1',operationType:'deviceVoiceMessage',direction:'DEVICE_TO_PLATFORM',source:'DIRECT_HELMET',reportAct:'ca_sending_message',deviceId:'helmet-1',personId:'person-old',personName:'接收时姓名',siteId:'site-1',receivedAt:'2026-11-02T08:00:00Z',timeBasis:'RECEIVED_AT',status:'READY',assetId:'asset-1',playable:true};
const ticket = (changes={}) => ({id:message.id,assetId:message.assetId,url:'https://media.example.invalid/helmet-media/files/asset-1?variant=playback&token=fixture-only',mime:'audio/mpeg',expiresAt:new Date(Date.now()+30000).toISOString(),...changes});

test('device voice messages preserve historical attribution and never represent a connected call',()=>{
  assert.equal(messages.isDeviceVoiceMessage(message),true);
  assert.equal(messages.isDeviceVoiceMessage({...message,operationType:'call'}),false);
  assert.equal(messages.isDeviceVoiceMessage({...message,source:'DIRECT_BELT'}),false);
  assert.equal(messages.isDeviceVoiceMessage({...message,timeBasis:'DEVICE_TIME'}),false);
  assert.equal(messages.voiceMessagePerson(message),'接收时姓名');
  assert.equal(messages.voiceMessagePerson({...message,personName:''}),'person-old（历史姓名未提供）');
  assert.equal(messages.voiceMessagePerson({...message,personName:'',personId:''}),'未关联人员');
  assert.equal(messages.voiceMessageStatus(message),'录音已收到');
  assert.match(messages.voiceMessageStatus({...message,status:'REJECTED'}),/未通过校验/);
  assert.match(messages.voiceMessageStatus({...message,playable:false}),/暂无可播放/);
  assert.doesNotMatch(messages.voiceMessageStatus(message),/通话|接通|已读/);
});

test('only a matching, unexpired HTTPS playback derivative can become an audio source',()=>{
  assert.equal(messages.voicePlaybackAuthorization(message,ticket()).mime,'audio/mpeg');
  for(const result of [ticket({id:'other'}),ticket({assetId:'other'}),ticket({mime:'audio/amr'}),ticket({expiresAt:'2000-01-01T00:00:00Z'}),ticket({expiresAt:''}),ticket({url:'http://media.example.invalid/helmet-media/files/asset-1?variant=playback'}),ticket({url:'https://user:pass@media.example.invalid/helmet-media/files/asset-1?variant=playback'}),ticket({url:'https://media.example.invalid/helmet-media/files/other?variant=playback'}),ticket({url:'https://media.example.invalid/helmet-media/files/asset-1?variant=original'}),ticket({url:'https://media.example.invalid/helmet-media/files/asset-1?variant=playback&variant=original'})]) assert.throws(()=>messages.voicePlaybackAuthorization(message,result));
  assert.throws(()=>messages.voicePlaybackAuthorization({...message,playable:false},ticket()));
  for(const expiresAt of ['2030-02-31T00:00:00Z','2030-01-01T00:00:00','2030-01-01T24:00:00Z','2030-01-01T00:00:00+99:00'])assert.throws(()=>messages.voicePlaybackAuthorization(message,ticket({expiresAt})));
  for(const suffix of ['?variant=playback','?variant=playback&token=','?variant=playback&token=t&token=other','?variant=playback&token=t&unexpected=1'])assert.throws(()=>messages.voicePlaybackAuthorization(message,ticket({url:'https://media.example.invalid/helmet-media/files/asset-1'+suffix})));
});

async function harness() {
  const raw=await readFile(new URL('../src/views/dispatch/DeviceVoiceMessages.vue',import.meta.url),'utf8');
  const {descriptor}=parse(raw),code=compileScript(descriptor,{id:'device-voice-message-test'}).content;
  const requests=[],watchers=[],unmount=[],intervals=[],auth=[];const tick=Vue.ref(0);
  const state={stations:[{id:'S1',siteId:'site-1'},{id:'S2',siteId:'site-2'}],operator:{id:'account',permissionsBySite:{'site-1':['communications:voice']}}};
  const session=Vue.reactive({station:'S1'});
  const authFetch=(url,options={})=>new Promise(resolve=>{assert.equal(options.method,undefined,'no device mutation request');requests.push({url,options,resolve});});
  const modules={vue:{...Vue,watch(selector,callback,options){watchers.push(callback);if(options?.immediate)callback();},onUnmounted(fn){unmount.push(fn);}},'@/mock/runtime':{db:{state}},'@/stores/session':{session},'@/lib/queries':{revision:()=>tick.value},'@/lib/auth':{authFetch,onAuthCleared(fn){auth.push(fn);return()=>{};}},'@/lib/date-time':dateTime,'@/lib/device-voice-messages':messages};
  const compiled=code.replace(/^import\s+([\s\S]*?)\s+from\s+(['"])([^'"]+)\2;?\s*$/gm,(_,names,_quote,from)=>{
    if(from.endsWith('.vue'))modules[from]={default:{}};
    assert.ok(modules[from],from);
    return `const ${names.trim().startsWith('{')?names.replace(/\bas\b/g,':'):`{default:${names}}`}=modules[${JSON.stringify(from)}];\n`;
  }).replace('export default','return');
  const component=new Function('modules','setInterval','clearInterval',compiled)(modules,fn=>{intervals.push(fn);return 1;},()=>{});
  const instance=component.setup({}, {expose(){}});
  const flush=async()=>{for(let index=0;index<8;index++)await Promise.resolve();};
  const respond=(request,body,status=200)=>request.resolve({ok:status===200,status,json:async()=>body});
  respond(requests.shift(),{rows:[message],total:1,pageNum:1,pageSize:5});await flush();
  const calls=[];const audio={pause(){calls.push('pause');},removeAttribute(name){calls.push('remove:'+name);},load(){calls.push('load');},play(){assert.fail('code must not autoplay a voice message');}};
  return {instance,requests,watchers,unmount,intervals,auth,state,session,tick,respond,flush,audio,calls};
}

test('listing never obtains a file or autoplays; explicit loading obtains only the selected message ticket',async()=>{
  const h=await harness();assert.equal(h.requests.length,0);assert.equal(h.instance.playback.value,null);
  const pending=h.instance.prepare(message);assert.match(h.requests[0].url,/\/voice-messages\/voice-1\/playback$/);
  h.respond(h.requests.shift(),ticket());await pending;
  assert.equal(h.instance.playback.value.id,message.id);assert.deepEqual(h.calls,[]);
  h.instance.setAudio(h.audio);h.instance.stopPlayback();assert.deepEqual(h.calls,['pause','remove:src','load']);assert.equal(h.instance.playback.value,null);
});

test('scope changes and unmount clear audio and discard late playback authorization',async()=>{
  const h=await harness();const pending=h.instance.prepare(message),old=h.requests.shift();
  h.session.station='S2';h.watchers[0]();h.respond(old,ticket());await pending;
  assert.equal(h.instance.playback.value,null);assert.equal(h.instance.rows.value.length,0);
  h.respond(h.requests.shift(),{rows:[{...message,siteId:'site-2'}],total:1});await h.flush();
  const next=h.instance.prepare({...message,siteId:'site-2'});h.respond(h.requests.shift(),ticket());await next;
  h.instance.setAudio(h.audio);h.unmount[0]();assert.deepEqual(h.calls,['pause','remove:src','load']);assert.equal(h.instance.playback.value,null);
  const count=h.requests.length;h.intervals[0]();assert.equal(h.requests.length,count);
});

test('same-account permission changes and auth clear stop playback without starting any call',async()=>{
  const h=await harness();const pending=h.instance.prepare(message);h.respond(h.requests.shift(),ticket());await pending;h.instance.setAudio(h.audio);
  h.state.operator.permissionsBySite={'site-1':[]};h.tick.value++;h.watchers[0]();
  assert.equal(h.instance.playback.value,null);assert.equal(h.instance.rows.value.length,0);assert.deepEqual(h.calls,['pause','remove:src','load']);
  h.auth[0]();const count=h.requests.length;h.intervals[0]();await h.instance.read();assert.equal(h.requests.length,count,'auth-cleared component stops polling');
});

test('a rejected playback request removes the message and an older list response cannot restore it',async()=>{
  const h=await harness();const list=h.instance.read(),old=h.requests.shift();
  const playback=h.instance.prepare(message),request=h.requests.shift();h.respond(request,{},403);await playback;
  h.respond(old,{rows:[message],total:1});await list;assert.equal(h.instance.rows.value.length,0);assert.equal(h.instance.playback.value,null);
  assert.match(h.instance.playbackError.value,/没有查看/);
});

test('list revocation stops an active file; temporary network errors retain only existing authorized metadata',async()=>{
  const h=await harness();let pending=h.instance.prepare(message);h.respond(h.requests.shift(),ticket());await pending;h.instance.setAudio(h.audio);
  pending=h.instance.read();h.respond(h.requests.shift(),{},503);await pending;assert.equal(h.instance.rows.value.length,1);
  pending=h.instance.read();h.respond(h.requests.shift(),{},403);await pending;assert.equal(h.instance.rows.value.length,0);assert.equal(h.instance.playback.value,null);assert.deepEqual(h.calls,['pause','remove:src','load']);
});

test('an expired ticket cannot start or resume playback and rejected messages never request a ticket',async()=>{
  const h=await harness();await h.instance.prepare({...message,playable:false});assert.equal(h.requests.length,0);
  const pending=h.instance.prepare(message);h.respond(h.requests.shift(),ticket());await pending;h.instance.setAudio(h.audio);
  h.instance.playback.value.expiresAt=Date.now()-1;h.instance.checkPlayback();
  assert.equal(h.instance.playback.value,null);assert.match(h.instance.playbackError.value,/已过期/);assert.deepEqual(h.calls,['pause','remove:src','load']);
});
