import test from 'node:test';
import assert from 'node:assert/strict';
import { createLiveVideoPlayer } from '../src/lib/live-video-player.js';

const live = (token='first', stream='stream1', protocol='WHEP') => ({
  protocol, streamId:stream, url:`https://media.test/helmet-media/${protocol==='HLS'?'hls':'whep'}/${stream}${protocol==='HLS'?'/index.m3u8':''}?token=${token}`,
  hlsUrl:`https://media.test/helmet-media/hls/${stream}/index.m3u8?token=${token}`, expiresAt:'2030-01-01T01:00:00Z',
});
function fixture(overrides={}) {
  const calls=[],states=[];
  const video={srcObject:null, pause(){},removeAttribute(){},load(){},canPlayType(){return '';},play:async()=>{}};
  const open=(source,_video,options)=>{
    let resolve;
    const call={source,options,closed:0,session:{close:async()=>{call.closed++;}}};
    call.ready=()=>{resolve(call.session);};calls.push(call);
    return new Promise(done=>{resolve=done;});
  };
  const player=createLiveVideoPlayer(video,{open,onChange:value=>states.push(value),...overrides});
  return {player,calls,states,video};
}
test('five-second ticket renewal does not abort pending WHEP negotiation or reset playing state',async()=>{
  const {player,calls,states}=fixture();
  const pending=player.update(live());
  for(let i=1;i<=12;i++) await player.update(live(`renewed-${i}`));
  assert.equal(calls.length,1);assert.equal(calls[0].options.signal.aborted,false);
  calls[0].ready();await pending;calls[0].options.onState('playing');
  await player.update(live('latest'));
  assert.equal(calls.length,1);assert.equal(calls[0].closed,0);assert.equal(states.at(-1).state,'playing');
  player.dispose();assert.equal(calls[0].closed,1);
});
test('failed connection stays actionable and explicit retry uses latest renewed credentials',async()=>{
  const {player,calls,states}=fixture();
  const initial=player.update(live());calls[0].ready();await initial;
  calls[0].options.onState('failed');await player.update(live('newest'));
  assert.equal(calls.length,1);assert.equal(states.at(-1).state,'failed');
  const retry=player.retry();assert.equal(calls.length,2);assert.equal(calls[0].closed,1);
  assert.match(calls[1].source.url,/token=newest$/);calls[1].ready();await retry;player.dispose();
});
test('stream change aborts old negotiation and late old completion cannot replace new session',async()=>{
  const {player,calls}=fixture();const first=player.update(live());const second=player.update(live('next','stream2'));
  assert.equal(calls.length,2);assert.equal(calls[0].options.signal.aborted,true);
  calls[1].ready();await second;calls[0].ready();await first;
  assert.equal(calls[0].closed,1);assert.equal(calls[1].closed,0);
  player.dispose();assert.equal(calls[1].closed,1);
});
test('a non-ticket URL change reconnects even with the same streamId',async()=>{
  const {player,calls}=fixture();const first=player.update(live());calls[0].ready();await first;
  const next=player.update({...live('new'),url:live('new').url+'&camera=2'});
  assert.equal(calls.length,2);assert.equal(calls[0].closed,1);calls[1].ready();await next;player.dispose();
});
test('invalid stream removes active media and expired retry never starts another WHEP',async()=>{
  const {player,calls,states}=fixture();const pending=player.update(live());calls[0].ready();await pending;
  await player.update({url:'javascript:bad',protocol:'WHEP'});assert.equal(calls[0].closed,1);assert.equal(states.at(-1).state,'failed');
  await player.update({...live('expired'),expiresAt:'2000-01-01T00:00:00Z'});
  assert.equal(calls.length,1);assert.match(states.at(-1).error,/过期/);player.dispose();
});
test('unmount cancels pending connection and cleans a late session without further status updates',async()=>{
  const {player,calls,states}=fixture();const pending=player.update(live());player.dispose();const count=states.length;
  assert.equal(calls[0].options.signal.aborted,true);calls[0].ready();await pending;calls[0].options.onState('playing');
  assert.equal(calls[0].closed,1);assert.equal(states.length,count);await player.update(live('ignored'));assert.equal(calls.length,1);
});
function fakeHls(supported=true) {
  const instances=[];
  class Hls {
    static Events={ERROR:'error',MANIFEST_PARSED:'parsed'};
    static isSupported(){return supported;}
    constructor(config){this.config=config;this.destroyed=0;this.events=new Map();instances.push(this);}
    on(event,handler){this.events.set(event,handler);} loadSource(url){this.url=url;} attachMedia(){} destroy(){this.destroyed++;}
  }
  return {instances,loadHls:async()=>({default:Hls})};
}
test('protocol switch closes WHEP and hls.js renews both playlists and segments without reload',async()=>{
  const hls=fakeHls(),{player,calls}=fixture({loadHls:hls.loadHls});
  const first=player.update(live());calls[0].ready();await first;await player.update(live('hls-first','stream1','HLS'));
  assert.equal(calls[0].closed,1);assert.equal(hls.instances.length,1);
  await player.update(live('hls-fresh','stream1','HLS'));assert.equal(hls.instances.length,1);
  const requests=[],xhr={open:(_method,url)=>requests.push(url)},config=hls.instances[0].config;
  config.xhrSetup(xhr,'https://media.test/helmet-media/hls/stream1/index.m3u8?token=hls-first');
  config.xhrSetup(xhr,'https://media.test/helmet-media/hls/stream1/stream1-10.ts?token=hls-first');
  assert.ok(requests.every(url=>url.endsWith('token=hls-fresh')));
  const fetched=config.fetchSetup({url:'https://media.test/helmet-media/hls/stream1/stream1-11.ts?token=old'},{});
  assert.match(fetched.url,/token=hls-fresh$/);player.dispose();assert.equal(hls.instances[0].destroyed,1);
});
test('HLS renewal never forwards the fresh ticket to other origins or stream directories',async()=>{
  const hls=fakeHls(),{player}=fixture({loadHls:hls.loadHls});await player.update(live('private','stream1','HLS'));
  const requests=[],xhr={open:(_method,url)=>requests.push(url)};
  const urls=['https://foreign.test/helmet-media/hls/stream1/a.ts?token=old','https://media.test/helmet-media/hls/stream2/a.ts?token=old'];
  for(const url of urls)hls.instances[0].config.xhrSetup(xhr,url);
  assert.deepEqual(requests,urls);player.dispose();
});
test('manual HLS fallback survives ticket polls, but a new stream returns to WHEP',async()=>{
  const hls=fakeHls(),{player,calls,states}=fixture({loadHls:hls.loadHls});
  const first=player.update(live());calls[0].ready();await first;await player.useHls();await player.update(live('fresh'));
  assert.equal(hls.instances.length,1);assert.equal(states.at(-1).fallback,true);
  const next=player.update(live('next','stream2'));assert.equal(hls.instances[0].destroyed,1);assert.equal(calls.length,2);
  assert.equal(states.at(-1).fallback,false);calls[1].ready();await next;player.dispose();
});
test('native HLS uses expiresAt for renewal instead of reconnecting on every poll',async()=>{
  let time=Date.parse('2030-01-01T00:00:00Z'),id=0;const timers=new Map(),cancelled=[];
  const {player,video}=fixture({loadHls:fakeHls(false).loadHls,now:()=>time,schedule:(fn,delay)=>{timers.set(++id,{fn,delay});return id;},cancel:key=>{cancelled.push(key);timers.delete(key);}});
  video.canPlayType=()=>true;await player.update(live('old','stream1','HLS'));
  const originalTimer=[...timers.values()][0];assert.equal(originalTimer.delay,3600000-15000);
  time+=5000;await player.update({...live('renewed','stream1','HLS'),expiresAt:'2030-01-01T01:00:05Z'});
  assert.match(video.src,/token=old$/);assert.equal(timers.size,1);
  time=Date.parse('2030-01-01T00:59:45Z');originalTimer.fn();await Promise.resolve();
  assert.match(video.src,/token=renewed$/);assert.equal(timers.size,1);
  player.dispose();assert.equal(timers.size,0);
});
test('hls.js is preferred even when Chrome advertises native HLS capability',async()=>{
  const hls=fakeHls(),{player,video}=fixture({loadHls:hls.loadHls});video.canPlayType=()=> 'maybe';
  await player.update(live('ticket','stream1','HLS'));
  assert.equal(hls.instances.length,1);assert.equal(video.src,undefined);player.dispose();
});
test('only autoplay denial asks for a click; unsupported playback and abort report actual errors',async()=>{
  for(const [name,expected] of [['NotAllowedError','playback_blocked'],['NotSupportedError','failed'],['AbortError','failed'],['UnknownError','failed']]){
    const hls=fakeHls(),{player,video,states}=fixture({loadHls:hls.loadHls});
    video.play=async()=>{throw Object.assign(Error('https://private.test/?token=SECRET'),{name});};
    await player.update(live('ticket','stream1','HLS'));
    hls.instances[0].events.get('parsed')();await Promise.resolve();await Promise.resolve();
    assert.equal(states.at(-1).state,expected);assert.equal(JSON.stringify(states).includes('SECRET'),false);
    if(name==='NotSupportedError')assert.match(states.at(-1).error,/格式/);
    player.dispose();
  }
});
test('native-only browser reports unsupported format rather than an autoplay prompt',async()=>{
  const {player,video,states}=fixture({loadHls:fakeHls(false).loadHls,now:()=>Date.parse('2030-01-01T00:00:00Z')});video.canPlayType=()=>true;
  video.play=async()=>{throw Object.assign(Error('private URL'),{name:'NotSupportedError'});};
  await player.update(live('ticket','stream1','HLS'));assert.equal(states.at(-1).state,'failed');assert.match(states.at(-1).error,/格式/);player.dispose();
});
test('HLS network HTTP status and media decode failures are visible without leaking signed URLs',async()=>{
  const hls=fakeHls(),{player,states,video}=fixture({loadHls:hls.loadHls});await player.update(live('ticket','stream1','HLS'));
  const emit=hls.instances[0].events.get('error');
  emit(null,{fatal:true,type:'networkError',response:{code:500,url:'https://private/?token=SECRET'}});
  assert.equal(states.at(-1).state,'failed');assert.match(states.at(-1).error,/HTTP 500/);
  emit(null,{fatal:true,type:'mediaError',error:Error('https://private/?token=SECRET')});assert.match(states.at(-1).error,/解码/);
  video.error={code:3,message:'https://private/?token=SECRET'};player.mediaError();assert.match(states.at(-1).error,/解码/);
  assert.equal(JSON.stringify(states).includes('SECRET'),false);player.dispose();
});
