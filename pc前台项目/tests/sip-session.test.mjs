import test from 'node:test';
import assert from 'node:assert/strict';
import { createSipSession } from '../src/lib/sip-session.js';

const credentials={protocol:'SIP',server:'wss://example.test/sip',uri:'sip:browser@example.test',target:'sip:room@example.test',authorizationUsername:'browser',authorizationPassword:'test-secret',iceServers:[{urls:'stun:example.test'}],video:true};
function emitter(){const listeners=new Set();return{addListener:fn=>listeners.add(fn),removeListener:fn=>listeners.delete(fn),emit:value=>listeners.forEach(fn=>fn(value))};}
function fixture({reject=false,waitRegistration=false,waitAnswer=false}={}){
  const seen=[],states=[],streams=[];
  const audioTrack={id:'remote-audio',kind:'audio',stop:()=>seen.push('remote-stop')}, videoTrack={id:'remote-video',kind:'video',stop:()=>seen.push('video-stop')};
  const microphone={kind:'audio',enabled:true,stop:()=>seen.push('microphone-stop')};
  const audio={pause:()=>seen.push('pause'),play:async()=>seen.push('play')};
  class UserAgent{
    static makeURI=value=>value;
    constructor(options){seen.push(['ua',options]);}
    async start(){seen.push('start');}async stop(){seen.push('stop');}
  }
  class Registerer{
    stateChange=emitter();
    async register(options){seen.push('register');if(reject)options.requestDelegate.onReject();else if(!waitRegistration)this.stateChange.emit('registered');}
    async unregister(){seen.push('unregister');}
  }
  let currentInviter;
  class Inviter{
    state='initial';stateChange=emitter();
    sessionDescriptionHandler={peerConnection:{getReceivers:()=>[{track:audioTrack},{track:videoTrack}],getSenders:()=>[{track:microphone}],addEventListener(){}}};
    constructor(_ua,_target,options){currentInviter=this;seen.push(['invite-options',options]);}
    async invite(){this.state=waitAnswer?'establishing':'established';this.stateChange.emit(this.state);}async bye(){seen.push('bye');}async cancel(){seen.push('cancel');}
  }
  const tracks=[];
  const deps={loadSip:async()=>({UserAgent,Registerer,Inviter,Web:{defaultSessionDescriptionHandlerFactory:factory=>factory},RegistererState:{Registered:'registered',Terminated:'terminated'},SessionState:{Initial:'initial',Establishing:'establishing',Established:'established',Terminated:'terminated'}}),makeAudio:()=>audio,makeStream:()=>({addTrack:track=>tracks.push(track),getTracks:()=>tracks,getAudioTracks:()=>tracks.filter(track=>track.kind==='audio'),getVideoTracks:()=>tracks.filter(track=>track.kind==='video')})};
  return{seen,states,streams,microphone,audio,deps,establish(){currentInviter.state='established';currentInviter.stateChange.emit('established');},events:{onMediaState:state=>states.push(state),onStream:stream=>streams.push(stream)}};
}
test('SIP registers, explicitly opts into camera, plays remote media and awaits single cleanup',async()=>{
  const f=fixture(),session=await createSipSession(credentials,f.events,f.deps);
  const ua=f.seen.find(row=>Array.isArray(row)&&row[0]==='ua')[1];
  assert.equal(ua.logBuiltinEnabled,false);
  assert.deepEqual(ua.sessionDescriptionHandlerFactoryOptions.peerConnectionConfiguration.iceServers,credentials.iceServers);
  assert.deepEqual(f.seen.find(row=>Array.isArray(row)&&row[0]==='invite-options')[1].sessionDescriptionHandlerOptions.constraints,{audio:true,video:true});
  assert.equal(f.states.at(-1),'remote_video');
  await session.setMuted(true);assert.equal(f.microphone.enabled,false);
  await Promise.all([session.close(),session.close()]);
  assert.equal(f.seen.filter(value=>value==='bye').length,1);
  assert.ok(f.seen.includes('microphone-stop'));assert.ok(f.seen.includes('remote-stop'));
  assert.equal(f.seen.at(-1),'stop');assert.equal(f.streams.at(-1),null);
});
test('SIP registration refusal cleans the transport without making a call',async()=>{
  const f=fixture({reject:true});
  await assert.rejects(createSipSession(credentials,f.events,f.deps),/注册被拒绝/);
  assert.equal(f.seen.some(row=>Array.isArray(row)&&row[0]==='invite-options'),false);
  assert.equal(f.seen.at(-1),'stop');
});
test('SIP pending registration can be cancelled without leaving a transport alive',async()=>{
  const f=fixture({waitRegistration:true}),controller=new AbortController();
  const joining=createSipSession(credentials,{...f.events,signal:controller.signal},f.deps);
  await new Promise(resolve=>setImmediate(resolve));controller.abort();
  await assert.rejects(joining,/取消/);assert.equal(f.seen.at(-1),'stop');
});

test('SIP INVITE submission does not report local membership before Established', async () => {
  const f=fixture({waitAnswer:true});
  const session=await createSipSession(credentials,f.events,f.deps);
  assert.deepEqual(f.states,['connecting_service','registering','preparing_offer','invite_sent']);
  assert.equal(f.states.includes('local_joined'),false);
  f.establish(); assert.ok(f.states.includes('local_joined')); assert.equal(f.states.at(-1),'remote_video');
  await session.close();
});
test('SIP SDP factory reuses the exact prepared audio stream and cleans it on close', async () => {
  const f=fixture(), stream={getTracks:()=>[f.microphone],getAudioTracks:()=>[f.microphone]};
  const session=await createSipSession({...credentials,video:false},{...f.events,microphoneStream:stream},f.deps);
  const options=f.seen.find(row=>Array.isArray(row)&&row[0]==='ua')[1];
  assert.equal(await options.sessionDescriptionHandlerFactory({audio:true,video:false}),stream);
  await assert.rejects(options.sessionDescriptionHandlerFactory({audio:true,video:true}),/麦克风不可用/);
  await session.close(); assert.ok(f.seen.includes('microphone-stop'));
});

test('resuming blocked playback updates actual media state; failures and late success cannot resurrect a closed call', async () => {
  const f=fixture(); f.audio.play=async()=>{throw Error('NotAllowedError');};
  const session=await createSipSession(credentials,f.events,f.deps);
  assert.equal(f.states.at(-1),'playback_blocked');
  await assert.rejects(session.resumeAudio(),/仍未允许播放/);
  assert.equal(f.states.at(-1),'playback_blocked');
  f.audio.play=async()=>{}; await session.resumeAudio();
  assert.equal(f.states.at(-1),'remote_video');
  let resume;
  f.audio.play=()=>new Promise(resolve=>{resume=resolve;});
  const pending=session.resumeAudio(); await session.close();
  const count=f.states.length; resume(); await pending;
  assert.equal(f.states.length,count);
  await assert.rejects(session.resumeAudio(),/通话已结束/);
});
