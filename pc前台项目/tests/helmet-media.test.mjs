import test from 'node:test';
import assert from 'node:assert/strict';
import { mediaUrl, createHelmetMediaApi, openWhep, whepDiagnosticSummary } from '../src/lib/helmet-media.js';
import { createStore, seed } from '../src/mock/data.js';

test('media transport rejects executable URLs and keeps retry command identity',async()=>{
  assert.equal(mediaUrl('javascript:alert(1)'),null);
  assert.equal(mediaUrl('https://user:secret@example.test/video'),null);
  const calls=[];
  const api=createHelmetMediaApi(async(url,options)=>{calls.push({url,options});return{ok:true,json:async()=>({status:'sent'})}});
  const result=await api.command('H/1','take_photo',{},'retry-key');
  assert.equal(result.status,'sent');assert.match(calls[0].url,/H%2F1/);
  assert.deepEqual(JSON.parse(calls[0].options.body),{action:'take_photo',parameters:{},idempotencyKey:'retry-key'});
});

test('SIP credentials never enter a persisted call snapshot',()=>{
  let saved;
  const store=createStore(null),state=seed();
  Object.assign(state.devices[0],{source:'DIRECT_HELMET',communicationProtocol:'SIP',freshness:'CURRENT',sourceTime:new Date().toISOString(),online:true,featureStates:{voice:{supported:true,verified:true,available:true}},capabilities:{actions:['intercom']}});
  store.replaceRemote(state);store.setRemoteCommit(value=>{saved=value});
  store.setVoice(()=>({protocol:'SIP',channel:'bridge',callId:'C1',authorizationPassword:'SENSITIVE-TEST-VALUE',authorizationUsername:'u',server:'wss://example.test',uri:'sip:a@example.test',target:'sip:b@example.test'}));
  const id=store.startCall(['P1'],'单呼');
  assert.equal(saved,undefined); // Client call UI state is never submitted as a server result.
  assert.equal(store.state.calls[0].rtc.callId,'C1');
  assert.equal(JSON.stringify(store.state).includes('SENSITIVE-TEST-VALUE'),false);
  store.applyServerCallStatus(id,{status:'connected',serverConnected:true,connectedDeviceIds:['RL-H001']});
  assert.equal(store.state.calls[0].serverConnected,true);
  assert.equal(store.state.calls[0].status,'通话中');
});

test('uncertain SIP call retains an endable record without attempting to join',async()=>{
  let joins=0,ends=0;
  const store=createStore(null,{loadRtc:async()=>({joinChannel:async()=>{joins++;},leaveChannel:async()=>{}})}),state=seed();
  Object.assign(state.devices[0],{source:'DIRECT_HELMET',communicationProtocol:'SIP',freshness:'CURRENT',sourceTime:new Date().toISOString(),online:true,featureStates:{voice:{supported:true,verified:true,available:true}},capabilities:{actions:['intercom']}});
  store.replaceRemote(state);store.setRemoteCommit(()=>{});
  store.setVoice(path=>{if(path.endsWith('/end')){ends++;return{ok:true};}return{protocol:'SIP',status:'unknown',channel:'SIP-test',callId:'SIP-test'};});
  const id=store.startCall(['P1'],'单呼');
  await assert.rejects(store.updateCall(id,'connect'),/未确认/);assert.equal(joins,0);
  await store.updateCall(id,'end');assert.equal(ends,1);assert.equal(store.state.calls[0].status,'正在结束');
  store.applyServerCallStatus(id,{status:'ended',serverConnected:false});assert.equal(store.state.calls[0].status,'已结束');
});

test('WHEP is receive-only and deletes only its same-origin session on cleanup',async()=>{
  const calls=[],tracks=[],events=new Map();let closed=0;
  class PC { constructor(){this.iceGatheringState='complete';this.localDescription={sdp:'offer'};}addTransceiver(kind,options){tracks.push([kind,options.direction]);}addEventListener(name,fn){events.set(name,fn);}async createOffer(){return{type:'offer',sdp:'offer'}}async setLocalDescription(){}async setRemoteDescription(answer){assert.equal(answer.sdp,'answer');}close(){closed++;}}
  const video={pause(){},srcObject:null};
  const fetchImpl=async(url,options)=>{calls.push([url,options.method]);return{ok:true,headers:new Headers({Location:'/session/1'}),text:async()=>'answer'}};
  const live=await openWhep({url:'https://example.test/camera/whep'},video,{fetchImpl,PeerConnection:PC,Stream:class{}});
  assert.deepEqual(tracks,[['video','recvonly'],['audio','recvonly']]);
  await live.close();await live.close();
  assert.equal(closed,1);assert.deepEqual(calls,[['https://example.test/camera/whep','POST'],['https://example.test/session/1','DELETE']]);
});

function whepFixture({fetchImpl,play=async()=>{},answerError}={}) {
  const events=new Map(),states=[];let pc;
  class PC {
    constructor(){pc=this;this.iceGatheringState='complete';this.localDescription={sdp:'offer'};}
    addTransceiver(){}addEventListener(name,handler){events.set(name,handler);}async createOffer(){return{type:'offer',sdp:'offer'};}
    async setLocalDescription(){}async setRemoteDescription(){if(answerError)throw answerError;}close(){}
  }
  class Stream {constructor(){this.tracks=[];}getTracks(){return this.tracks;}addTrack(track){this.tracks.push(track);}}
  const video={pause(){},srcObject:null,play};
  const options={PeerConnection:PC,Stream,fetchImpl:fetchImpl||(async()=>({ok:true,headers:new Headers(),text:async()=>'answer'})),onState:(state,error)=>states.push({state,error})};
  return {events,states,video,options,getPc:()=>pc};
}
test('WHEP HTTP failures expose a status code but never a signed URL',async()=>{
  const fixture=whepFixture({fetchImpl:async()=>({ok:false,status:500})});
  await assert.rejects(openWhep({url:'https://private.test/whep?token=SECRET'},fixture.video,fixture.options),reason=>/HTTP 500/.test(reason.message)&&!reason.message.includes('SECRET'));
});
test('WHEP network and SDP failures expose the phase without raw exception details',async()=>{
  for(const [options,expected] of [[{fetchImpl:async()=>{throw Error('https://private/?token=SECRET');}},/请求未完成/],[{answerError:Error('SDP SECRET')},/应答无法解析/]]){
    const fixture=whepFixture(options);
    await assert.rejects(openWhep({url:'https://private.test/whep?token=SECRET'},fixture.video,fixture.options),reason=>expected.test(reason.message)&&!reason.message.includes('SECRET'));
  }
});
test('WHEP ICE failure and unsupported track playback remain distinct from autoplay denial',async()=>{
  for(const name of ['NotAllowedError','NotSupportedError']){
    const fixture=whepFixture({play:async()=>{throw Object.assign(Error('SECRET'),{name});}});
    const opened=await openWhep({url:'https://media.test/whep'},fixture.video,fixture.options);
    fixture.events.get('track')({track:{id:'v1'}});await Promise.resolve();await Promise.resolve();
    assert.equal(fixture.states.at(-1).state,name==='NotAllowedError'?'playback_blocked':'failed');
    fixture.getPc().iceConnectionState='failed';fixture.events.get('iceconnectionstatechange')();
    assert.match(fixture.states.at(-1).error,/ICE failed/);assert.equal(JSON.stringify(fixture.states).includes('SECRET'),false);
    await opened.close();
  }
});
test('WHEP diagnostics contain only allowed states, candidate types, transports and counts',()=>{
  const stats=new Map([
    ['local',{type:'local-candidate',candidateType:'relay',protocol:'udp',address:'SECRET-IP',port:9876,url:'turn:SECRET',usernameFragment:'SECRET'}],
    ['remote',{type:'remote-candidate',candidateType:'host',protocol:'udp',address:'SECRET-IP',port:8000}],
    ['pair',{type:'candidate-pair',state:'failed',nominated:false,requestsSent:7,responsesReceived:0,requestsReceived:0,responsesSent:0,localCandidateId:'local',remoteCandidateId:'remote',id:'SECRET'}],
    ['transport',{type:'transport',dtlsState:'new',remoteCertificateId:'SECRET',selectedCandidatePairId:'SECRET'}],
    ['certificate',{type:'certificate',base64Certificate:'SECRET'}],
  ]);
  const result=whepDiagnosticSummary({connectionState:'failed',iceConnectionState:'failed',localDescription:'SECRET'},stats);
  assert.equal(result.pairs[0].requestsSent,7);assert.equal(result.pairs[0].responsesReceived,0);
  assert.deepEqual(result.pairs[0].local,{type:'relay',protocol:'udp'});assert.equal(result.transports[0].dtlsState,'new');
  assert.equal(JSON.stringify(result).includes('SECRET'),false);assert.equal(JSON.stringify(result).includes('8000'),false);
});
test('WHEP diagnostics reject arbitrary strings and invalid counters rather than logging them',()=>{
  const stats=new Map([
    ['l',{type:'local-candidate',candidateType:'SECRET',protocol:'SECRET'}],
    ['p',{type:'candidate-pair',state:'SECRET',localCandidateId:'l',remoteCandidateId:'missing',requestsSent:'SECRET',responsesReceived:Infinity}],
    ['t',{type:'transport',dtlsState:'SECRET'}],
  ]);
  const result=whepDiagnosticSummary({connectionState:'SECRET',iceConnectionState:'SECRET'},stats);
  assert.equal(JSON.stringify(result).includes('SECRET'),false);assert.equal(result.pairs[0].requestsSent,null);
  assert.equal(result.connectionState,null);assert.equal(result.transports[0].dtlsState,null);
});
