import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {createHash,createHmac} from 'node:crypto';
import {MediaAdapter,SessionJournal} from '../media.mjs';

const leaseId='GB_media_test_0123456789';
const expectedKey=`__defaultVhost__/fuda_gb/${leaseId}`;
const tracks=[{codec_type:0,codec_id_name:'CodecH264',ready:true},{codec_type:1,codec_id_name:'CodecAAC',ready:true}];
const response=body=>new Response(JSON.stringify(body),{headers:{'Content-Type':'application/json'}});
function fixture(overrides={}){
  const calls=[],state={tracks:structuredClone(tracks),fail:new Set(),...overrides};
  const config={javaOrigin:'http://127.0.0.1:8080',javaSecret:'unit-java-signing-key-never-use-outside-tests',zlmOrigin:'http://127.0.0.1:18194',zlmSecret:'unit-zlm-key-never-use-outside-tests',srsOrigin:'rtmp://127.0.0.1:1935',sourceTimeoutMs:1000,requireAudio:true};
  const journal=new SessionJournal(null);
  const row={leaseId,localPort:31000,channel:{deviceId:'real-helmet-source'},media:{ip:'127.0.0.1',port:30050,pt:96,ssrc:'100000001',tcp:false},abort:new AbortController()};
  const fetcher=async(url,options)=>{
    const u=new URL(url);
    if(u.pathname.startsWith('/index/api/')){
      const api=u.pathname.split('/').at(-1),input=Object.fromEntries(options.body);
      calls.push({api,input});if(state.fail.has(api))throw Error('mock network failure');
      if(api==='addStreamProxy'){
        assert.equal(journal.rows[leaseId].proxyKey,expectedKey,'Cleanup identity must be durable before the proxy can exist');
        if(state.afterProxy)await state.afterProxy();
        if(state.proxyTimeouts>0){state.proxyTimeouts--;return response({code:-1,msg:'play rtmp timeout'});}
        if(state.proxyError)return response({code:-1,msg:state.proxyError});
        return response({code:0,data:{key:state.proxyKey??expectedKey}});
      }
      if(api==='getMediaInfo')return response({code:0,tracks:state.tracks});
      if(api==='startSendRtp')return response({code:0,local_port:state.localPort??Number(input.src_port)});
      if(api==='stopSendRtp'&&state.senderAbsent)return response({code:-1});
      if(api==='delStreamProxy'){if(state.afterDelete)await state.afterDelete();return response({code:0,data:{flag:true}});}
      return response({code:0});
    }
    const body=options.body??'',headers=options.headers;
    const signed=`${headers['X-GB-Time']}\n${headers['X-GB-Nonce']}\n${options.method}\n${u.pathname}\n${createHash('sha256').update(body).digest('hex')}`;
    assert.equal(headers['X-GB-Signature'],createHmac('sha256',config.javaSecret).update(signed).digest('hex'));
    calls.push({api:'java',method:options.method,path:u.pathname});
    if(state.fail.has(options.method))throw Error('mock network failure');
    return response({code:200,data:options.method==='DELETE'?{released:true}:{online:true,publishing:true,statusVerified:true,busy:false,streamId:'real-source-id',playToken:'unit-scoped.playback-ticket-0123456789',...state.source}});
  };
  return {media:new MediaAdapter(config,{fetcher,journal}),row,state,calls,journal,config};
}

test('official CodecH264/CodecAAC tracks produce scoped PS/RTP with the requested source port',async()=>{
  const f=fixture();await f.media.prepare(f.row,f.row.abort.signal);await f.media.start(f.row);
  assert.deepEqual(f.row.tracks,{video:'H264',audio:'AAC'});assert.ok(f.row.rtpStartedAt);
  const proxy=f.calls.find(x=>x.api==='addStreamProxy').input;
  assert.equal(proxy.add_mute_audio,'0');assert.equal(proxy.retry_count,'0');assert.equal(proxy.app,'fuda_gb');
  assert.match(proxy.url,/^rtmp:\/\/127\.0\.0\.1:1935\/helmet\/real-source-id\?token=/);
  const rtp=f.calls.find(x=>x.api==='startSendRtp').input;
  assert.equal(rtp.use_ps,'1');assert.equal(rtp.pt,'96');assert.equal(rtp.src_port,'31000');assert.equal(rtp.dst_port,'30050');
  assert.equal(rtp.ssrc,'100000001');assert.equal(rtp.is_udp,'1');
});

test('unready, absent or unsupported actual tracks never claim successful audio/video',async()=>{
  for(const [source,code]of [
    [[{codec_type:0,codec_id_name:'H265',ready:true},tracks[1]],'GB_UNSUPPORTED_VIDEO'],
    [[tracks[0],{codec_type:1,codec_id_name:'Opus',ready:true}],'GB_UNSUPPORTED_AUDIO'],
    [[{...tracks[0],ready:false},tracks[1]],'GB_TRACKS_NOT_READY'],
    [[tracks[0]],'GB_TRACKS_NOT_READY'],
    [[{codec_type:0,codec_id_name:'H264'},tracks[1]],'GB_TRACKS_NOT_READY']
  ]){
    const f=fixture({tracks:source});f.config.sourceTimeoutMs=300;
    await assert.rejects(f.media.prepare(f.row,f.row.abort.signal),{code});
    assert.ok(!f.calls.some(x=>x.api==='startSendRtp'));await f.media.release(f.row);
    assert.deepEqual(f.journal.rows,{});
  }
});

test('explicit video-only mode does not synthesize an audio track',async()=>{
  const f=fixture({tracks:[tracks[0]]});f.config.requireAudio=false;
  await f.media.prepare(f.row,f.row.abort.signal);assert.deepEqual(f.row.tracks,{video:'H264',audio:null});
  assert.equal(f.calls.find(x=>x.api==='addStreamProxy').input.add_mute_audio,'0');
});

test('pinned ZLM AAC RTP encoding name mpeg4-generic remains real AAC',async()=>{
  const f=fixture({tracks:[{codec_type:0,codec_id_name:'H264',codec_id:0,ready:true},{codec_type:1,codec_id_name:'mpeg4-generic',codec_id:2,ready:true}]});
  await f.media.prepare(f.row,f.row.abort.signal);await f.media.renew(f.row);
  assert.deepEqual(f.row.tracks,{video:'H264',audio:'AAC'});
});

test('a cold source may retry only explicit ZLM media timeout after private proxy removal',async()=>{
  const f=fixture({proxyTimeouts:1});await f.media.prepare(f.row,f.row.abort.signal);
  assert.deepEqual(f.calls.filter(x=>['addStreamProxy','delStreamProxy'].includes(x.api)).map(x=>x.api),['addStreamProxy','delStreamProxy','addStreamProxy']);
  assert.deepEqual(f.row.tracks,{video:'H264',audio:'AAC'});
  assert.ok(f.calls.filter(x=>x.api==='addStreamProxy').every(x=>Number(x.input.timeout_sec)<=1));
});

test('authentication, protocol and ambiguous network failures never trigger proxy retries',async()=>{
  for(const proxyError of ['play 失败:error NetStream.Play.Failed','connect 失败:error NetConnection.Connect.Rejected','connection refused','This stream already exists']){
    const f=fixture({proxyError});await assert.rejects(f.media.prepare(f.row,f.row.abort.signal),{code:'GB_MEDIA_OPERATION_FAILED'});
    assert.equal(f.calls.filter(x=>x.api==='addStreamProxy').length,1);assert.ok(f.journal.rows[leaseId]);
  }
  const f=fixture({fail:new Set(['addStreamProxy'])});await assert.rejects(f.media.prepare(f.row,f.row.abort.signal),{code:'GB_CONTROL_UNAVAILABLE'});
  assert.equal(f.calls.filter(x=>x.api==='addStreamProxy').length,1);
});

test('source retries stop at the original budget, three attempts, cancellation or failed cleanup',async()=>{
  const budget=fixture({proxyTimeouts:10,afterProxy:()=>new Promise(r=>setTimeout(r,200))});budget.config.sourceTimeoutMs=350;
  await assert.rejects(budget.media.prepare(budget.row,budget.row.abort.signal),{code:'GB_SOURCE_TIMEOUT'});
  assert.equal(budget.calls.filter(x=>x.api==='addStreamProxy').length,1);
  const capped=fixture({proxyTimeouts:10});capped.config.sourceTimeoutMs=10000;
  await assert.rejects(capped.media.prepare(capped.row,capped.row.abort.signal),{code:'GB_MEDIA_OPERATION_FAILED'});
  assert.equal(capped.calls.filter(x=>x.api==='addStreamProxy').length,3);
  const cancelled=fixture({proxyTimeouts:1});cancelled.state.afterDelete=()=>cancelled.row.abort.abort();
  await assert.rejects(cancelled.media.prepare(cancelled.row,cancelled.row.abort.signal),{code:'GB_CANCELLED'});
  assert.equal(cancelled.calls.filter(x=>x.api==='addStreamProxy').length,1);
  const cleanup=fixture({proxyTimeouts:1,fail:new Set(['delStreamProxy'])});
  await assert.rejects(cleanup.media.prepare(cleanup.row,cleanup.row.abort.signal),{code:'GB_CONTROL_UNAVAILABLE'});
  assert.equal(cleanup.calls.filter(x=>x.api==='addStreamProxy').length,1);assert.ok(cleanup.journal.rows[leaseId]);
});

test('a different RTP source port cannot be reported as an established stream',async()=>{
  const f=fixture({localPort:31002});await f.media.prepare(f.row,f.row.abort.signal);
  await assert.rejects(f.media.start(f.row),{code:'GB_RTP_PORT_MISMATCH'});assert.equal(f.row.rtpStartedAt,undefined);
  await f.media.release(f.row);assert.deepEqual(f.journal.rows,{});
});

test('CANCEL during proxy creation still discovers and removes the eventual private proxy',async()=>{
  const f=fixture();f.state.afterProxy=async()=>{f.row.abort.abort();};
  await assert.rejects(f.media.prepare(f.row,f.row.abort.signal),{code:'GB_CANCELLED'});
  assert.equal(f.calls.filter(x=>x.api==='getMediaInfo').length,0);await f.media.release(f.row);
  assert.deepEqual(f.calls.filter(x=>x.api==='delStreamProxy').map(x=>x.input.key),[expectedKey]);
  assert.equal(f.calls.filter(x=>x.api==='java'&&x.method==='DELETE').length,1);
});

test('lost proxy creation response remains recoverable and never closes the shared source',async()=>{
  const f=fixture({fail:new Set(['addStreamProxy'])});
  await assert.rejects(f.media.prepare(f.row,f.row.abort.signal),{code:'GB_CONTROL_UNAVAILABLE'});
  assert.equal(f.journal.rows[leaseId].proxyKey,expectedKey);
  f.state.fail.clear();await f.media.recover();assert.deepEqual(f.journal.rows,{});
  for(const c of f.calls.filter(x=>['delStreamProxy','stopSendRtp','close_streams'].includes(x.api))){
    if(c.api==='delStreamProxy')assert.equal(c.input.key,expectedKey);
    else{assert.equal(c.input.app,'fuda_gb');assert.equal(c.input.stream,leaseId);}
  }
  assert.ok(!f.calls.some(x=>x.api==='close_streams'));
});

test('failed lease or proxy release retains the durable cleanup record for retry',async()=>{
  for(const failure of ['DELETE','delStreamProxy']){
    const f=fixture();await f.media.prepare(f.row,f.row.abort.signal);f.state.fail.add(failure);
    assert.equal(await f.media.release(f.row),false);assert.ok(f.journal.rows[leaseId]);
    f.state.fail.clear();f.state.senderAbsent=true;
    assert.equal(await f.media.release(f.row),true);assert.deepEqual(f.journal.rows,{});
  }
});

test('renewal detects lost real audio instead of extending a falsely healthy stream',async()=>{
  const f=fixture();await f.media.prepare(f.row,f.row.abort.signal);await f.media.start(f.row);
  f.state.tracks=[tracks[0]];await assert.rejects(f.media.renew(f.row),{code:'GB_TRACKS_NOT_READY'});
});

test('restart recovery reloads only cleanup identity and preserves active sessions',async t=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'gb-media-test-'));
  t.after(()=>{fs.rmSync(filename,{force:true});fs.rmSync(filename+'.tmp',{force:true});fs.rmdirSync(dir);});
  const filename=path.join(dir,'journal.json'),journal=new SessionJournal(filename);
  const f=fixture();journal.put({...f.row,proxyKey:expectedKey,sourceUrl:'must-not-persist',playToken:'must-not-persist'});
  const disk=fs.readFileSync(filename,'utf8');assert.ok(!disk.includes('must-not-persist'));
  f.media.journal=new SessionJournal(filename);
  await f.media.cleanupOrphans(new Set([leaseId]));assert.ok(f.media.journal.rows[leaseId]);assert.equal(f.calls.length,0);
  await f.media.recover();assert.deepEqual(new SessionJournal(filename).rows,{});
});

test('malformed recovery identity cannot invoke another stream or lease',async()=>{
  const f=fixture();f.journal.rows['bad']={leaseId:'../shared/stream',proxyKey:'__defaultVhost__/helmet/shared'};
  await assert.rejects(f.media.recover());assert.equal(f.calls.length,0);
});

test('control transport rejects redirects, malformed JSON objects and oversized response bodies',async()=>{
  for(const body of ['null','[]','"unexpected"','{',JSON.stringify({data:'x'.repeat(1024*1024)})]){
    let options;const media=new MediaAdapter({},{journal:new SessionJournal(null),fetcher:async(u,o)=>{options=o;return new Response(body);}});
    await assert.rejects(media.json('http://127.0.0.1:18194/test',{}),e=>['GB_CONTROL_INVALID_RESPONSE','GB_CONTROL_RESPONSE_TOO_LARGE'].includes(e.code));
    assert.equal(options.redirect,'error');
  }
});
