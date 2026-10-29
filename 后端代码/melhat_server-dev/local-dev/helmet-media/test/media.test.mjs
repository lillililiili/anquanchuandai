import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { once } from 'node:events';
import { createHash } from 'node:crypto';
import { verifier, signedHeaders, signedDigestHeaders, ticket, readTicket } from '../auth.mjs';
import { Store } from '../store.mjs';
import { MediaService, CONTROL } from '../service.mjs';
import { createServer } from '../server.mjs';
import { frameDecoder } from '../esl.mjs';

function fixture(t) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'helmet-media-test-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const config = { signingKey: 'a'.repeat(43), turnSecret: 'b'.repeat(43), hookKey: 'c'.repeat(43), eslPassword: 'd'.repeat(43),
    dataDir: directory, publicOrigin: 'https://media.example.com', publicIp: '203.0.113.4', sipHost: '203.0.113.4',
    srsApi: 'http://127.0.0.1:19850', srsHttp: 'http://127.0.0.1:18080', ttsOrigin: 'http://127.0.0.1:18192' };
  const commands = [];
  const service = new MediaService(config, { command: async c => { commands.push(c); return c.includes('registrations') ? '{"rows":[]}' : c==='status'?'UP 0 years':c==='sofia status'?'helmet\tprofile\tsip:mod_sofia@203.0.113.4:5060\tRUNNING (0)':' +OK'; },
    fetch: async url => new Response(JSON.stringify(url.endsWith('/health') ? { ready: true } : { code: 0, streams: [], clients: [] })) });
  return { config, service, commands };
}
test('live playback tickets expire with the viewer lease while publishing remains independent', t => {
  const { config, service } = fixture(t);
  const now = Date.now(), stream = service.createStream({ deviceId: 'device1', sessionId: 'session1' });
  const play = new URL(stream.hlsUrl).searchParams.get('token');
  const publish = new URL(stream.pushUrl).searchParams.get('token');
  assert.ok(readTicket(config.signingKey, play, now));
  assert.equal(readTicket(config.signingKey, play, now + 31000), null);
  assert.ok(readTicket(config.signingKey, publish, now + 31000));
  assert.ok(Date.parse(stream.expiresAt) - now <= 31000);
});

test('HMAC binds exact method/path/body and rejects replay or expired signatures', () => {
  const key = 'a'.repeat(43), now = 1800000000000, body = Buffer.from('{"a":1}');
  const headers = signedHeaders(key, 'POST', '/test?x=1', body, now);
  const request = { method: 'POST', url: '/test?x=1', headers: Object.fromEntries(Object.entries(headers).map(([k,v]) => [k.toLowerCase(),v])) };
  const verify = verifier(key, () => now);
  assert.equal(verify({ ...request, url: '/test?x=2' }, body), false);
  assert.equal(verify(request, Buffer.from('{}')), false);
  assert.equal(verify(request, body), true);
  assert.equal(verify(request, body), false);
  assert.equal(verifier(key, () => now + 100000)(request, body), false);
});
test('signed file and playback tickets cannot change scope or survive expiry', () => {
  const key = 'x'.repeat(43), value = ticket(key, { purpose: 'asset', id: 'a', exp: 2000 });
  assert.equal(readTicket(key, value, 1000000).id, 'a');
  assert.equal(readTicket(key, value, 3000000), null);
  assert.equal(readTicket(key, value.replace(/.$/, 'x'), 1000000), null);
});
test('account provisioning returns a secure WebSocket SIP endpoint for helmet and operator clients', async t => {
  const { service } = fixture(t);
  for (const [publicOrigin, expected] of [
    ['https://media.example.com', 'wss://media.example.com/helmet-media/sip'],
    ['https://media.example.com:8443/', 'wss://media.example.com:8443/helmet-media/sip'],
  ]) {
    service.config.publicOrigin = publicOrigin;
    for (const kind of ['helmet', 'operator']) {
      const response = await service.putAccount(kind + '1', { kind, password: 'p'.repeat(32),
        ...(kind === 'helmet' ? { deviceId: 'device1' } : { expiresAt: Date.now() + 60000, roomId: 'room1' }) });
      assert.equal(response.wssUrl, expected);
      assert.match(response.wssUrl, /^wss:\/\//i);
      assert.equal(new URL(response.wssUrl).pathname, '/helmet-media/sip');
      assert.equal(response.sipHost, '203.0.113.4');
    }
  }
});
test('operator requires bounded expiry and room; SIP directory and dialplan reject expired/unrelated targets', async t => {
  const { service } = fixture(t);
  await assert.rejects(service.putAccount('op1', { kind: 'operator', password: 'p'.repeat(32) }), /OPERATOR_SCOPE_REQUIRED/);
  await service.putAccount('op1', { kind: 'operator', password: 'p'.repeat(32), expiresAt: Date.now()+60000, roomId: 'room1' });
  service.store.data.calls.c1 = { callId: 'c1', roomId: 'room1', status: 'dialing' };
  assert.match(service.directory(new URLSearchParams({ section: 'directory', user: 'op1', domain: '203.0.113.4' })), /password/);
  assert.match(service.directory(new URLSearchParams({ section: 'dialplan', variable_sip_auth_username: 'op1', 'Caller-Destination-Number': 'room1' })), /conference/);
  assert.match(service.directory(new URLSearchParams({ section: 'dialplan', variable_sip_auth_username: 'op1', 'Caller-Destination-Number': 'another' })), /not found/);
  service.store.data.accounts.op1.expiresAt = Date.now()-1;
  assert.match(service.directory(new URLSearchParams({ section: 'directory', user: 'op1', domain: '203.0.113.4' })), /not found/);
  assert.match(service.directory(new URLSearchParams({ section: 'dialplan', variable_sip_auth_username: 'op1', 'Caller-Destination-Number': 'room1' })), /not found/);
});
test('connected event requires actual helmet and operator answers', async t => {
  const { service } = fixture(t);
  await service.putAccount('hat1', { kind: 'helmet', password: 'p'.repeat(32), deviceId: 'device1' });
  await service.startCall({ callId:'c1', roomId:'room1', participants:['hat1'] });
  const uuid = Object.keys(service.store.data.calls.c1.legs)[0];
  service.handleEsl({ 'Event-Name':'CHANNEL_ANSWER', 'Unique-ID':uuid, variable_helmet_call_id:'c1' });
  assert.equal(service.store.data.calls.c1.status,'answered');
  assert.equal(service.store.data.events.some(e=>e.type==='call.connected'),false);
  service.handleEsl({ 'Event-Name':'CHANNEL_ANSWER', 'Unique-ID':'operator-leg', variable_helmet_call_id:'c1' });
  assert.equal(service.store.data.calls.c1.status,'connected');
  assert.deepEqual(service.store.data.events.at(-1).connectedDeviceIds,['device1']);
});

test('video call includes real video codecs and a video conference profile', async t => {
  const { service, commands } = fixture(t);
  await service.putAccount('hat1', {kind:'helmet', password:'p'.repeat(32), deviceId:'d1'});
  const call = await service.startCall({callId:'v1', roomId:'vr1', participants:['hat1'], video:true});
  assert.equal(call.video,true); assert.match(commands.at(-1),/PCMA,H264,VP8/); assert.match(commands.at(-1),/@helmet-video/);
  await service.putAccount('op1',{kind:'operator',password:'q'.repeat(32),roomId:'vr1',expiresAt:Date.now()+60000});
  assert.match(service.directory(new URLSearchParams({section:'dialplan', variable_sip_auth_username:'op1', 'Caller-Destination-Number':'vr1'})), /vr1@helmet-video/);
});
test('SRS publication requires matching stream publish ticket; readiness is not registration', async t => {
  const { service } = fixture(t);
  const stream = service.createStream({ deviceId:'d1',sessionId:'session1' });
  assert.equal(service.handleSrs({ app:'helmet',stream:stream.streamId,action:'on_publish',param:'?token=bad' }),1);
  assert.equal(service.handleSrs({ app:'helmet',stream:stream.streamId,action:'on_publish',param:new URL(stream.pushUrl).search }),0);
  assert.equal((await service.health()).ready,true);
  assert.deepEqual((await service.health()).devices,[]);
  const state = await service.streamState(stream.streamId);
  assert.equal(state.publishing,false); assert.equal(state.statusVerified,true);
});
test('FreeSWITCH readiness accepts its right-aligned real profile table with LF or CRLF', async t => {
  const { service } = fixture(t);
  const rows = [
    '                     Name\t   Type\t                                      Data\tState',
    '=================================================================================================',
    '                   helmet\tprofile\t  sip:mod_sofia@203.0.113.4:5060\tRUNNING (0)',
    '=================================================================================================',
    '1 profile 0 aliases',
  ];
  for (const newline of ['\n', '\r\n']) {
    service.command = async command => command === 'status' ? 'UP 0 years, 0 days' :
      command === 'sofia status' ? rows.join(newline) : '{"rows":[]}';
    const health = await service.health();
    assert.deepEqual(health.components, { freeswitch: true, srs: true, tts: true });
    assert.equal(health.ready, true);
    assert.deepEqual(health.devices, []);
  }
});
test('FreeSWITCH readiness requires the helmet profile itself to be RUNNING', async t => {
  const { service } = fixture(t);
  const reports = [
    '                   helmet\tprofile\tsip:mod_sofia@203.0.113.4:5060\tDOWN (0)\n' +
      '                 external\tprofile\tsip:mod_sofia@203.0.113.4:5080\tRUNNING (0)',
    '             helmet-video\tprofile\tsip:mod_sofia@203.0.113.4:5060\tRUNNING (0)',
    '                   helmet\talias\texternal\tRUNNING (0)',
    '                   helmet\tprofile\tsip:mod_sofia@203.0.113.4:5060\tRUNNING_OTHER (0)',
    '                   helmet\tprofile\nexternal\tRUNNING (0)',
    '',
  ];
  for (const report of reports) {
    service.command = async command => command === 'status' ? 'UP 0 years, 0 days' :
      command === 'sofia status' ? report : '{"rows":[]}';
    const health = await service.health();
    assert.equal(health.components.freeswitch, false);
    assert.equal(health.ready, false);
  }
});
test('multipart photo identity and magic validation; cloud asset survives service restart', async t => {
  const { service,config } = fixture(t);
  const multipart = value => Buffer.concat([Buffer.from(`--bound\r\nContent-Disposition: form-data; name="device_id"\r\n\r\n${value}\r\n--bound\r\nContent-Disposition: form-data; name="file"; filename="../../x.jpg"\r\nContent-Type: image/jpeg\r\n\r\n`),Buffer.from([255,216,255,0,0]),Buffer.from('\r\n--bound--\r\n')]);
  await assert.rejects(service.ingestUpload(multipart('other'),'multipart/form-data; boundary=bound','device1','photo'),/DEVICE_MISMATCH/);
  const result = await service.ingestUpload(multipart('device1'),'multipart/form-data; boundary=bound','device1','photo');
  assert.equal(result.kind,'photo'); assert.equal(Object.hasOwn(result,'filename'),false);
  const restored = new Store(config.dataDir); assert.equal(restored.data.assets[result.assetId].deviceId,'device1');
});
test('ESL frames handle fragmented header/body and multiple messages', () => {
  const frames=[]; const decode=frameDecoder((h,b)=>frames.push([h,b]));
  decode(Buffer.from('Content-Type: api/response\nContent-Length: 4\n\nab'));
  assert.equal(frames.length,0);
  decode(Buffer.from('cdContent-Type: auth/request\n\n'));
  assert.equal(frames.length,2); assert.equal(frames[0][1],'abcd');
});
test('HTTP control rejects unsigned requests and publicly inaccessible management paths', async t => {
  const { config,service }=fixture(t), {server}=createServer(config,{service});
  server.listen(0,'127.0.0.1'); await once(server,'listening'); t.after(()=>new Promise(r=>server.close(r)));
  const origin=`http://127.0.0.1:${server.address().port}`;
  assert.equal((await fetch(origin+CONTROL+'/health')).status,401);
  assert.equal((await fetch(origin+'/api/v1/clients')).status,404);
  const headers=signedHeaders(config.signingKey,'GET',CONTROL+'/health');
  const r=await fetch(origin+CONTROL+'/health',{headers}); assert.equal(r.status,200); assert.equal((await r.json()).data.ready,true);
  assert.equal((await fetch(origin+CONTROL+'/health',{headers})).status,401);
});

test('HLS proxies only a validated play ticket to internal SRS for playlists and segments', async t => {
  const { config, service } = fixture(t);
  const stream = service.createStream({ deviceId: 'd1', sessionId: 'hls1' });
  const other = service.createStream({ deviceId: 'd2', sessionId: 'hls2' });
  const playToken = new URL(stream.hlsUrl).searchParams.get('token');
  const route = `/helmet-media/hls/${stream.streamId}/`;
  const calls = [];
  service.fetch = async (url, options) => {
    const target = new URL(url);
    calls.push({ target, options });
    if (service.handleSrs({ app: 'helmet', stream: stream.streamId, action: 'on_play', param: target.search }) !== 0)
      return new Response('Denied by SRS callback', { status: 403 });
    return new Response(target.pathname.endsWith('.m3u8')
      ? `#EXTM3U\n#EXTINF:2,\n${stream.streamId}-0.ts\n` : new Uint8Array([0x47, 0x01, 0x02]));
  };
  const { server } = createServer(config, { service });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(() => new Promise(resolve => server.close(resolve)));
  const origin = `http://127.0.0.1:${server.address().port}`;
  for (const invalid of ['', 'bad', new URL(other.hlsUrl).searchParams.get('token')]) {
    assert.equal((await fetch(origin + route + 'index.m3u8?token=' + encodeURIComponent(invalid))).status, 403);
  }
  assert.equal(calls.length, 0);
  const playlist = await fetch(origin + route + 'index.m3u8?token=' + encodeURIComponent(playToken));
  assert.equal(playlist.status, 200);
  assert.match(await playlist.text(), new RegExp(`${stream.streamId}-0\\.ts\\?token=`));
  const segment = await fetch(origin + route + `${stream.streamId}-0.ts?token=` + encodeURIComponent(playToken));
  assert.equal(segment.status, 200);
  assert.deepEqual([...new Uint8Array(await segment.arrayBuffer())], [0x47, 0x01, 0x02]);
  assert.deepEqual(calls.map(call => call.target.pathname), [`/helmet/${stream.streamId}.m3u8`, `/helmet/${stream.streamId}-0.ts`]);
  for (const call of calls) {
    assert.equal(call.target.origin, new URL(config.srsHttp).origin);
    assert.equal(call.target.searchParams.get('token'), playToken);
    assert.equal(call.options.redirect, 'error');
  }
  service.store.data.streams[stream.streamId].status = 'stopped';
  assert.equal((await fetch(origin + route + 'index.m3u8?token=' + encodeURIComponent(playToken))).status, 403);
  assert.equal(calls.length, 2);
});

test('SRS HLS on_play normalizes only a same-stream m3u8 filename and retains ticket scope', t => {
  const { service } = fixture(t);
  const stream = service.createStream({ deviceId: 'd1', sessionId: 'hls-hook' });
  const other = service.createStream({ deviceId: 'd2', sessionId: 'other-hook' });
  const input = { app: 'helmet', action: 'on_play', stream: stream.streamId + '.m3u8', param: new URL(stream.hlsUrl).search };
  assert.equal(service.handleSrs(input), 0);
  for (const change of [{param:'?token=bad'}, {param:new URL(other.hlsUrl).search}, {app:'other'},
    {stream:'../'+input.stream}, {stream:input.stream+'.m3u8'}, {stream:input.stream+'.ts'},
    {action:'on_publish',param:new URL(stream.pushUrl).search}]) assert.equal(service.handleSrs({...input,...change}), 1);
  service.store.data.streams[stream.streamId].status = 'stopped';
  assert.equal(service.handleSrs(input), 1);
});

test('SRS HLS master and media playlists retain context through the authorized public path', async t => {
  const { config, service } = fixture(t);
  const stream = service.createStream({ deviceId: 'd1', sessionId: 'hls-context' });
  const token = new URL(stream.hlsUrl).searchParams.get('token'), context = 'ctx12345', calls = [];
  service.fetch = async (value, options) => {
    const target = new URL(value); calls.push(target);
    assert.equal(options.redirect, 'error');
    assert.equal(target.origin, new URL(config.srsHttp).origin);
    assert.equal(target.searchParams.get('token'), token);
    if (target.pathname.endsWith('.ts')) return new Response(new Uint8Array([0x47, 0x01]));
    assert.equal(service.handleSrs({app:'helmet',action:'on_play',stream:stream.streamId+'.m3u8',param:target.search}), 0);
    return new Response(target.searchParams.has('hls_ctx')
      ? `#EXTM3U\n#EXTINF:2,\n${stream.streamId}-0.ts?hls_ctx=${context}\n`
      : `#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\n/helmet/${stream.streamId}.m3u8?hls_ctx=${context}&token=${token}\n`);
  };
  const { server } = createServer(config, { service });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(() => new Promise(resolve => server.close(resolve)));
  const origin = `http://127.0.0.1:${server.address().port}`, route = `/helmet-media/hls/${stream.streamId}/index.m3u8?token=${token}`;
  const master = await fetch(origin + route); assert.equal(master.status, 200);
  const child = (await master.text()).split('\n').find(line => line && !line.startsWith('#'));
  assert.ok(child.startsWith('index.m3u8?'));
  const childUrl = new URL(child, origin + route);
  assert.equal(childUrl.searchParams.get('hls_ctx'), context);
  const media = await fetch(childUrl); assert.equal(media.status, 200);
  const segment = (await media.text()).split('\n').find(line => line && !line.startsWith('#'));
  const segmentUrl = new URL(segment, childUrl);
  assert.equal(segmentUrl.searchParams.get('token'), token);
  assert.equal(segmentUrl.searchParams.get('hls_ctx'), context);
  assert.equal((await fetch(segmentUrl)).status, 200);
  assert.equal(calls.length, 3);
  assert.equal(calls[0].searchParams.has('hls_ctx'), false);
  assert.equal(calls[1].searchParams.get('hls_ctx'), context);
  assert.equal(calls[2].searchParams.get('hls_ctx'), context);
});

test('HLS resource rewrite rejects external, other-stream, ambiguous or malformed destinations', async t => {
  const { config, service } = fixture(t);
  const stream = service.createStream({ deviceId: 'd1', sessionId: 'hls-denials' });
  const token = new URL(stream.hlsUrl).searchParams.get('token');
  let resource = '', upstreamCalls = 0;
  service.fetch = async () => { upstreamCalls++; return new Response('#EXTM3U\n' + resource + '\n'); };
  const { server } = createServer(config, { service });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(() => new Promise(resolve => server.close(resolve)));
  const origin = `http://127.0.0.1:${server.address().port}`, route = `${origin}/helmet-media/hls/${stream.streamId}/index.m3u8?token=${token}`;
  for (resource of [
    `https://outside.invalid/helmet/${stream.streamId}.m3u8`, `other-stream-0.ts`, `../helmet/${stream.streamId}.m3u8`,
    `${stream.streamId}.m3u8?token=another`, `${stream.streamId}.m3u8?hls_ctx=short`,
    `${stream.streamId}.m3u8?hls_ctx=ctx12345&hls_ctx=ctx67890`, `${stream.streamId}.m3u8?next=elsewhere`,
    `${stream.streamId}.m3u8#fragment`, `#EXT-X-MEDIA:URI="${stream.streamId}.m3u8",URI=invalid`,
  ]) assert.equal((await fetch(route)).status, 502);
  const callsBefore = upstreamCalls;
  for (const query of ['&hls_ctx=short', '&hls_ctx=ctx12345&hls_ctx=ctx67890', '&token=' + token, '&next=elsewhere'])
    assert.equal((await fetch(route + query)).status, 400);
  assert.equal(upstreamCalls, callsBefore);
});

test('hangup remains ending on failed ESL; only observed channel disappearance confirms end',async t=>{
 const {service}=fixture(t);await service.putAccount('h1',{kind:'helmet',password:'p'.repeat(32),deviceId:'d1'});
 await service.startCall({callId:'c1',roomId:'r1',participants:['h1']});
 service.command=async()=>{throw Error('offline')};
 assert.equal((await service.endCall('c1')).status,'ending');assert.equal(service.store.data.events.some(e=>e.type==='call.ended'),false);
 service.store.data.calls.c1.createdAt=new Date(Date.now()-60000).toISOString();
 service.command=async c=>c.startsWith('uuid_exists')?'false':'+OK';
 assert.equal((await service.endCall('c1')).status,'ended');
 assert.equal((await service.endCall('unknown')).status,'ended');
 assert.equal((await service.startCall({callId:'unknown',roomId:'r2',participants:['h1']})).status,'ended');
});

test('photo binding rejects another owner and preserves uploaded GCJ-02 metadata',async t=>{
 const {service}=fixture(t),assetId='photo1';
 service.store.data.assets[assetId]={assetId,deviceId:'d1',kind:'photo'};
 const input={deviceId:'d1',imageUrl:'https://media.example.com/helmet-media/files/photo1?token=expired',latitude:'22',longitude:'114'};
 assert.equal(service.bindPhoto(input).status,'ready');assert.equal(service.store.data.assets[assetId].coordinateSystem,'GCJ-02');
 assert.throws(()=>service.bindPhoto({...input,deviceId:'other'}),/ASSET_OWNER_MISMATCH/);
});

test('uncertain start and late answer remain cancelling until every real leg is absent',async t=>{
 const {service}=fixture(t);await service.putAccount('h1',{kind:'helmet',password:'p'.repeat(32),deviceId:'d1'});
 service.command=async()=>{throw Error('ESL disconnected after originate write')};
 assert.equal((await service.startCall({callId:'race1',roomId:'room1',participants:['h1']})).status,'ending');
 const call=service.store.data.calls.race1,uuid=Object.keys(call.legs)[0];
 service.handleEsl({'Event-Name':'CHANNEL_ANSWER','Unique-ID':uuid,variable_helmet_call_id:'race1'});
 await new Promise(r=>setImmediate(r));
 assert.equal(call.status,'ending');assert.equal(service.store.data.events.some(e=>['call.connected','call.failed','call.ended'].includes(e.type)),false);
 service.command=async c=>c.startsWith('uuid_exists')?'false':'+OK';
 assert.equal((await service.endCall('race1')).status,'ended');
 assert.deepEqual((await service.callState('race1')).connectedDeviceIds,[]);
});

test('queued origination is not declared ended before its deadline; actual ESL state reconciles missed events',async t=>{
 const {service}=fixture(t);await service.putAccount('h1',{kind:'helmet',password:'p'.repeat(32),deviceId:'d1'});
 await service.startCall({callId:'queued1',roomId:'room1',participants:['h1']});
 const call=service.store.data.calls.queued1;call.createdAt=new Date(Date.now()-6000).toISOString();
 service.command=async c=>c.startsWith('uuid_exists')?'false':'+OK';
 assert.equal((await service.callState('queued1')).status,'dialing');
 assert.equal((await service.endCall('queued1')).status,'ending');
 call.createdAt=new Date(Date.now()-60000).toISOString();
 assert.equal((await service.callState('queued1')).status,'ended');
 await service.startCall({callId:'reconcile1',roomId:'room2',participants:['h1']});
 const active=service.store.data.calls.reconcile1;active.createdAt=new Date(Date.now()-60000).toISOString();active.operatorUuid='operator-uuid';
 service.command=async c=>c.startsWith('uuid_exists')?'true':c.includes('answered_epoch')?'1800000000':'+OK';
 assert.equal((await service.callState('reconcile1')).status,'connected');
 assert.deepEqual((await service.callState('reconcile1')).connectedDeviceIds,['d1']);
 service.command=async c=>c.startsWith('uuid_exists')?'false':'+OK';
 assert.equal((await service.callState('reconcile1')).status,'ended');
});

test('recordings interrupted by restart become persistent failed events with correlation',t=>{
 const {service,config}=fixture(t);
 for(const status of ['starting','recording','finalizing'])service.store.data.recordings[status]={recordingId:status,deviceId:'d1',requestId:'req-'+status,status};
 service.store.save();const restored=new Store(config.dataDir);
 for(const status of ['starting','recording','finalizing'])assert.equal(restored.data.recordings[status].status,'interrupted');
 assert.equal(restored.data.events.filter(e=>e.type==='recording.failed'&&e.deviceId==='d1'&&e.requestId==='req-'+e.recordingId).length,3);
 assert.equal(new Store(config.dataDir).data.events.filter(e=>e.type==='recording.failed').length,3);
});

test('streamed upload verifies signed digest before durable success and rejects body changes',async t=>{
 const {config,service}=fixture(t),{server}=createServer(config,{service});
 server.listen(0,'127.0.0.1');await once(server,'listening');t.after(()=>new Promise(r=>server.close(r)));
 const origin=`http://127.0.0.1:${server.address().port}`,route=CONTROL+'/device-upload?deviceId=d1&kind=photo';
 const body=Buffer.concat([Buffer.from('--b\r\nContent-Disposition: form-data; name="file"; filename="x.jpg"\r\nContent-Type: image/jpeg\r\n\r\n'),Buffer.from([255,216,255,0]),Buffer.from('\r\n--b--\r\n')]);
 const digest=createHash('sha256').update(body).digest('hex');
 const signed=()=>({...signedDigestHeaders(config.signingKey,'POST',route,digest),'Content-Type':'multipart/form-data; boundary=b'});
 const ok=await fetch(origin+route,{method:'POST',headers:signed(),body});
 assert.equal(ok.status,200);const asset=(await ok.json()).data;assert.equal(asset.status,'ready');assert.equal(new Store(config.dataDir).data.assets[asset.assetId].deviceId,'d1');
 const bad=await fetch(origin+route,{method:'POST',headers:signed(),body:Buffer.concat([body,Buffer.from('tampered')])});
 assert.equal(bad.status,400);assert.equal((await bad.json()).error,'BODY_DIGEST_MISMATCH');assert.equal(Object.keys(service.store.data.assets).length,1);
});
