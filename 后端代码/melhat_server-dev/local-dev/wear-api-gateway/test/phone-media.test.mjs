import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { createServer, request } from 'node:http';
import { once } from 'node:events';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createWearGateway } from '../gateway.mjs';

// Executed only in isolated headless test clients, with Chromium's synthetic microphone.
async function handset(person, relayMode) {
  const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
  const clientId = crypto.randomUUID();
  async function action(name, args = {}) {
    const r = await fetch('/api/guardian/v1/mobile/phone/' + name, {
      method:'POST', headers:{'content-type':'application/json','x-wearable-token':person[0].repeat(43)},
      body:JSON.stringify({clientId, siteId:'s1', ...args}),
    });
    if (!r.ok) throw Error(name + ' HTTP ' + r.status);
    return r.json();
  }
  async function until(poll) {
    for (let i=0; i<100; i++) {
      const result = await poll();
      if (result) return result;
      await wait(400);
    }
    throw Error('Test phone did not reach the expected state');
  }
  const trace=async message=>{if(relayMode!=='local') await fetch('/trace/'+person,{method:'POST',body:message});};
  let pc, mic, pulse, stage = 'ringing';
  const candidateErrors=[];
  try {
    let call;
    if (person === 'alice') {
      await until(async () => (await action('presence')).contacts.includes('bob'));
      call=(await action('start',{personIds:['bob'],requestId:crypto.randomUUID()})).call;
    } else {
      call=await until(async () => (await action('presence')).call);
      if(call.members.find(m=>m.id===call.self).state !== 'ringing') throw Error('Missing incoming call');
      call=(await action('accept',{callId:call.id})).call;
    }
    call=await until(async()=>{
      const c=(await action('presence')).call;
      return c?.members.every(m=>m.state==='accepted') && c;
    });
    pulse=setInterval(()=>action('presence').catch(()=>{}),4000);
    const other=call.members.find(m=>m.id!==call.self).id;
    stage='microphone';
    mic=await navigator.mediaDevices.getUserMedia({audio:true,video:false});
    const forceRelay = relayMode === 'both' || relayMode === person;
    pc=new RTCPeerConnection({iceServers:call.iceByPeer[other],iceTransportPolicy:forceRelay?'relay':'all'});
    pc.onicecandidateerror=e=>candidateErrors.push([e.errorCode,e.url?.split(':')[0]].join('/'));
    for(const track of mic.getAudioTracks()) pc.addTrack(track,mic);
    const remoteAudio=new Audio();
    pc.ontrack=e=>{remoteAudio.srcObject=e.streams[0];remoteAudio.play().catch(()=>{});};
    const readRemote=async()=>{
      const signal=await until(async()=>(await action('presence')).call?.signals.find(s=>s.from===other));
      await pc.setRemoteDescription({type:signal.type,sdp:signal.sdp});
    };
    const offer=call.self<other;
    stage='remote offer';
    if(!offer) await readRemote();
    stage='ICE gathering';
    await pc.setLocalDescription(offer ? await pc.createOffer() : await pc.createAnswer());
    const started=performance.now();
    await until(()=>pc.iceGatheringState==='complete' || performance.now()-started>=12000);
    const candidates=pc.localDescription.sdp.match(/typ (host|srflx|relay|prflx)/g)||[];
    await trace(stage+' '+(offer?'offer':'answer')+' '+candidates.join(',')+' '+candidateErrors.join(','));
    if(!pc.localDescription.sdp.includes('a=candidate:')) throw Error('No local ICE candidate');
    await action('signal',{callId:call.id,to:other,type:pc.localDescription.type,sdp:pc.localDescription.sdp});
    stage='remote answer';
    if(offer) await readRemote();
    stage='incoming RTP';
    await trace(stage);
    const received=await until(async()=>{
      for(const s of (await pc.getStats()).values()) {
        if(s.type==='inbound-rtp' && s.kind==='audio' && pc.connectionState==='connected' &&
            s.packetsReceived>=8 && s.totalAudioEnergy>0) return {packets:s.packetsReceived,bytes:s.bytesReceived};
      }
    });
    const stats=await pc.getStats();
    const transport=[...stats.values()].find(s=>s.type==='transport' && s.selectedCandidatePairId);
    const pair=transport && stats.get(transport.selectedCandidatePairId);
    received.candidate=pair && stats.get(pair.localCandidateId)?.candidateType;
    if(forceRelay && received.candidate!=='relay') throw Error('No selected relay candidate');
    await fetch('/received/'+person,{method:'POST',body:JSON.stringify(received)});
    await until(async()=>(await (await fetch('/both')).text())==='yes');
    if(person==='alice') await action('leave',{callId:call.id});
    else await until(async()=>!(await action('presence')).call);
    await fetch('/finished/'+person,{method:'POST'});
  } catch(e) {
    let detail='';
    if(pc) {
      const stats=await pc.getStats();
      detail=[...stats.values()].filter(s=>s.type==='candidate-pair').map(s=>{
        const local=stats.get(s.localCandidateId), remote=stats.get(s.remoteCandidateId);
        return [local?.candidateType,remote?.candidateType,s.state,s.responsesReceived].join('/');
      }).slice(0,12).join(',');
    }
    await fetch('/failed/'+person,{method:'POST',body:[stage, String(e), pc?.iceConnectionState, candidateErrors.join(','), detail].join(' ')});

  } finally {clearInterval(pulse); pc?.close(); for(const t of mic?.getTracks()??[]) t.stop(); }
}

test('two isolated clients negotiate real microphone audio through the phone gateway', {
  skip: !process.env.WEAR_RTC_BROWSER, timeout: 125000,
}, async t => {
  const people = ['alice','bob'];
  const testRelays=JSON.parse(process.env.WEAR_RTC_TEST_ICE || '[]');
  const relayMode=process.env.WEAR_RTC_TEST_MODE || 'local';
  if(relayMode!=='local') assert.equal(testRelays.length,2);
  let nextRelay=0;
  const gateway=createWearGateway({testOnly:true,upstreamOrigin:'http://127.0.0.1:1',phoneOptions:{
    relay:()=>testRelays.length?testRelays[nextRelay++ % testRelays.length]:[], identity:async token=>{
      const id=people.find(p=>p[0].repeat(43)===token);
      if(!id) throw Error('Unknown fixture identity');
      return {id,name:id,personId:id,canDial:true,visible:new Map(people.map(p=>[p,p]))};
    },
  }});
  gateway.listen(0,'127.0.0.1'); await once(gateway,'listening');
  const received=new Map(), finished=new Set();
  let resolve, reject;
  const done=new Promise((ok,fail)=>{resolve=ok;reject=fail;});
  const app=createServer(async(req,res)=>{
    const url=new URL(req.url,'http://localhost');
    if(url.pathname.startsWith('/api/guardian/v1/mobile/phone/')){
      const proxy=request({hostname:'127.0.0.1',port:gateway.address().port,path:req.url,method:req.method,headers:req.headers},r=>{
        res.writeHead(r.statusCode,r.headers);r.pipe(res);
      });
      req.pipe(proxy);return;
    }
    const [,action,person]=url.pathname.split('/');
    if(action==='both'){res.end(received.size===2?'yes':'no');return;}
    if(!people.includes(person)){res.writeHead(404);res.end();return;}
    if(action==='client'){
      res.setHeader('content-type','text/html');res.end('<!doctype html><title>Phone integration fixture</title><script>('+handset.toString()+')('+JSON.stringify(person)+','+JSON.stringify(relayMode)+')</script>');return;
    }
    let body='';for await(const chunk of req) body+=chunk;
    if(action==='trace'){console.log('QA',person,body);}
    if(action==='received') received.set(person,JSON.parse(body));
    if(action==='finished'){finished.add(person);if(finished.size===2) resolve();}
    if(action==='failed') reject(Error(person+': '+body));
    res.end('ok');
  });
  app.listen(0,'127.0.0.1'); await once(app,'listening');
  const children=[];
  const profileRoot=path.resolve(tmpdir());
  try {
    for(const person of people){
      const dir=await mkdtemp(path.join(profileRoot,'wear-phone-rtc-'));
      const child=spawn(process.env.WEAR_RTC_BROWSER,[
        '--headless=new','--disable-gpu','--disable-extensions','--disable-background-networking','--disable-sync',
        '--disable-component-update','--no-first-run','--no-default-browser-check','--use-fake-device-for-media-stream',
        '--use-fake-ui-for-media-stream','--autoplay-policy=no-user-gesture-required','--no-proxy-server',
        '--disable-features=WebRtcHideLocalIpsWithMdns','--user-data-dir='+dir,
        'http://127.0.0.1:'+app.address().port+'/client/'+person,
      ],{stdio:'ignore',windowsHide:true});
      child.once('error',reject);
      children.push({child,dir});
    }
    const timeout=setTimeout(()=>reject(Error('Headless phone test timed out')),100000);
    try {await done;} finally {clearTimeout(timeout);}
    for(const person of people) assert.ok(received.get(person).bytes>0);
    t.diagnostic('Received audio packets: '+JSON.stringify(Object.fromEntries(received)));
  } finally {
    for(const {child,dir} of children){
      if(child.exitCode===null && !child.signalCode){const stopped=once(child,'exit');child.kill();await stopped;}
      if(path.dirname(path.resolve(dir))===profileRoot && path.basename(dir).startsWith('wear-phone-rtc-')) {
        await rm(dir,{recursive:true,force:true,maxRetries:8,retryDelay:200}).catch(()=>{});
      }
    }
    await Promise.all([app,gateway].map(s=>new Promise(r=>s.close(r))));
  }
});
