import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { randomBytes } from 'node:crypto';
import { once } from 'node:events';
import { setTimeout as delay } from 'node:timers/promises';
import { WebSocket, WebSocketServer } from 'ws';
import { createDeviceGateway } from '../gateway.mjs';
import { DEFAULTS, DEVICE_ID, validateConfig } from '../config.mjs';

const login = { act: 'ca_login', device_id: DEVICE_ID };
const report = { act: 'ca_report_location', device_id: DEVICE_ID, bat_l: 51, is_weared: 1 };

async function waitFor(check, timeout = 1500) {
  const deadline = Date.now() + timeout;
  while (!check()) { if (Date.now() > deadline) throw new Error('Timed out waiting for isolated fixture'); await delay(5); }
}
async function fixture(t, { limits = {}, mode = 'valid', upgradeDelay = 0, onGpsReport, mediaFetch } = {}) {
  const state = { requests: 0, upgrades: 0, messages: [], requestUrls: [], mode };
  const sockets = new Set();
  const upstream = http.createServer(async (_request, response) => {
    state.requests++;
    state.requestUrls.push(_request.url);
    if(_request.method==='POST'){const chunks=[];for await(const chunk of _request)chunks.push(chunk);state.lastBody=JSON.parse(Buffer.concat(chunks));response.setHeader('Content-Type','application/json');response.end(JSON.stringify({status:true,msg:'stored'}));return;}
    if (state.mode === 'hang') return;
    if (state.mode === 'redirect') { response.writeHead(302, { Location: 'http://127.0.0.1:18084/' }); response.end(); return; }
    if (state.mode === 'invalid') { response.end('invalid json'); return; }
    if (state.mode === 'oversize') { response.end('x'.repeat(70000)); return; }
    if (state.mode === 'failure') { response.writeHead(503); response.end(); return; }
    const payload = { status: true, msg_code: 'GetSucc', data: { time: 1,
      config: JSON.stringify({ api_url: 'http://private.invalid/api/', ws_url: 'ws://private.invalid/wsHat' }),
      extra: { watch_mac: '' } } };
    response.setHeader('Content-Type', 'application/json');
    response.end(JSON.stringify(payload));
  });
  upstream.on('connection', socket => { sockets.add(socket); socket.on('close', () => sockets.delete(socket)); });
  const wss = new WebSocketServer({ noServer: true });
  upstream.on('upgrade', (request, socket, head) => {
    assert.equal(request.url, '/wsHat');
    state.upgrades++;
    const accept = () => {
      if (socket.destroyed) return;
      wss.handleUpgrade(request, socket, head, ws => {
        ws.on('error', () => {});
        ws.on('message', (raw, binary) => {
          assert.equal(binary, false);
          state.messages.push(JSON.parse(raw.toString()));
          const act = state.messages.at(-1).act;
          const status = act === 'ca_login' ? state.loginAck !== false
            : act === 'toggle_localrecord' ? state.localRecordAck !== false
              : state.reportAck !== false || act !== 'ca_report_location';
          ws.send(JSON.stringify({ status,
            cmd: state.reportError && act === 'ca_report_location' ? 'error' : act }));
        });
      });
    };
    if (upgradeDelay) setTimeout(accept, upgradeDelay); else accept();
  });
  upstream.listen(0, '127.0.0.1');
  await once(upstream, 'listening');
  const upstreamPort = upstream.address().port;
  assert.notEqual(upstreamPort, 18084, 'Fixture must never use the daily backend');
  const config = { ...DEFAULTS, listenPort: 0, pathToken: randomBytes(32).toString('base64url'),
    upstreamOrigin: `http://127.0.0.1:${upstreamPort}`, publicOrigin: 'https://helmet.example.com' };
  if (mediaFetch) { config.mediaControlOrigin=config.publicOrigin; config.mediaSigningKey=randomBytes(32).toString('base64url'); }
  const gateway = createDeviceGateway(config, { testOnly: true, limits: { closeTimeoutMs: 30, ...limits }, onGpsReport, mediaFetch });
  const address = await gateway.listen();
  const origin = `http://127.0.0.1:${address.port}`;
  const basePath = `/${config.pathToken}/api/index.php`;
  const query = `?ctl=config&act=get_config&device_id=${DEVICE_ID}`;
  const wsUrl = `ws://127.0.0.1:${address.port}/${config.pathToken}/wsHat`;
  t.after(async () => {
    await gateway.close();
    for (const socket of sockets) socket.destroy();
    for (const ws of wss.clients) ws.terminate();
    await new Promise(resolve => wss.close(resolve));
    await new Promise(resolve => upstream.close(resolve));
  });
  return { gateway, config, state, wss, origin, basePath, query, wsUrl };
}
function getRaw(f, path, options = {}) {
  return new Promise((resolve, reject) => {
    const request = http.request(f.origin, { path, method: options.method ?? 'GET', headers: options.headers }, response => {
      let body = '';
      response.setEncoding('utf8'); response.on('data', chunk => { body += chunk; });
      response.on('end', () => resolve({ status: response.statusCode, body }));
    });
    request.on('error', reject); request.end();
  });
}
async function connect(url) {
  const ws = new WebSocket(url);
  ws.on('error', () => {});
  await once(ws, 'open');
  return ws;
}
async function exchange(ws, payload) {
  const response = once(ws, 'message');
  ws.send(typeof payload === 'string' ? payload : JSON.stringify(payload));
  return JSON.parse((await response)[0].toString());
}
function closed(ws) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Socket did not close')), 1500);
    ws.once('close', code => { clearTimeout(timer); resolve(code); });
  });
}
async function deniedUpgrade(url) {
  const ws = new WebSocket(url);
  ws.on('error', () => {});
  return new Promise((resolve, reject) => {
    ws.once('open', () => { ws.terminate(); reject(new Error('Unexpected upgrade')); });
    ws.once('unexpected-response', (_request, response) => {
      response.resume(); ws.terminate(); resolve(response.statusCode);
    });
  });
}

test('production config requires a private 32-byte credential, loopback and actual HTTPS origin', () => {
  const valid = { ...DEFAULTS, publicOrigin: 'https://helmet.example.com', pathToken: randomBytes(32).toString('base64url') };
  assert.equal(validateConfig(valid).deviceId, DEVICE_ID);
  for (const changed of [{ pathToken: '' }, { pathToken: 'a'.repeat(42) }, { publicOrigin: DEFAULTS.publicOrigin },
    { publicOrigin: 'http://helmet.example.com' }, { publicOrigin: 'https://127.0.0.1' },
    { publicOrigin: 'https://helmet.example.com/path' }, { listenHost: '0.0.0.0' },
    { upstreamOrigin: 'http://other.invalid' }, { deviceId: 'other' }]) {
    assert.throws(() => validateConfig({ ...valid, ...changed }));
  }
  assert.throws(() => validateConfig(valid, { testOnly: true }), 'Test mode must reject the daily backend');
});

test('bootstrap rewrites string config, omits accessory defaults and ignores forwarded Host', async t => {
  const f = await fixture(t);
  const response = await getRaw(f, f.basePath + f.query, { headers: { Host: 'attacker.invalid', 'X-Forwarded-Host': 'attacker.invalid' } });
  assert.equal(response.status, 200);
  const payload = JSON.parse(response.body), config = JSON.parse(payload.data.config);
  assert.equal(typeof payload.data.config, 'string');
  assert.equal(config.api_url, `${f.config.publicOrigin}/${f.config.pathToken}/api/`);
  assert.equal(new URL('index.php', config.api_url).pathname, f.basePath);
  assert.equal(config.ws_url, `wss://helmet.example.com/${f.config.pathToken}/wsHat`);
  assert.equal(Object.hasOwn(payload.data, 'extra'), false);
  assert.equal(f.state.requests, 1);
});

test('real firmware query metadata is validated and discarded before proxying', async t => {
  const f = await fixture(t);
  const metadata = new URLSearchParams({ app_version: 'M6811_58', ic: '', ca_ver: 'Android 7.1.2 / build+1' });
  assert.equal((await getRaw(f, f.basePath + f.query + '&' + metadata)).status, 200);
  const forwarded = new URL(f.state.requestUrls[0], f.config.upstreamOrigin);
  assert.deepEqual([...forwarded.searchParams.keys()], ['ctl','act','device_id']);
  for (const extra of ['&ic=x&ic=y','&ca_ver=%00','&app_version='+'a'.repeat(257),'&ic=%ZZ']) {
    assert.equal((await getRaw(f, f.basePath + f.query + extra)).status, 400);
  }
  assert.equal(f.state.requests, 1);
});

test('unlisted paths, encoded paths, extra/duplicate query and wrong IDs never reach upstream', async t => {
  const f = await fixture(t);
  const denied = ['/api/admin/v1/state', '/api/guardian/v1/snapshot', '/wsHat', '/wrong/api/index.php',
    `${f.basePath}/`, `/${f.config.pathToken}/x/../api/index.php`, `/${f.config.pathToken}/api/%69ndex.php`,
    f.basePath, f.basePath + f.query + '&unknown=x', f.basePath + f.query + '&device_id=' + DEVICE_ID,
    f.basePath + f.query.replace(DEVICE_ID, 'wrong'), f.basePath + f.query.replace('ctl', '%63tl'),
    f.basePath + f.query + '#fragment'];
  for (const path of denied) assert.ok((await getRaw(f, path)).status >= 400);
  assert.equal(f.state.requests, 0);
});

test('uploads fail explicitly and non-GET methods do not proxy', async t => {
  const f = await fixture(t);
  const response = await getRaw(f, f.basePath + '?ctl=file&act=upload', { method: 'POST' });
  assert.equal(response.status, 501);
  assert.deepEqual(JSON.parse(response.body), { status: false, msg_code: 'Unsupported', msg: 'Device request unavailable' });
  assert.equal((await getRaw(f, f.basePath + f.query, { method: 'PUT' })).status, 405);
  assert.equal(f.state.requests, 0);
});

for (const mode of ['redirect','invalid','oversize','failure','hang']) {
  test(`bootstrap ${mode} upstream is bounded and returns generic failure`, async t => {
    const f = await fixture(t, { mode, limits: { upstreamTimeoutMs: 120 } });
    const response = await getRaw(f, f.basePath + f.query);
    assert.equal(response.status, 502);
    assert.equal(response.body.includes(f.config.pathToken), false);
    assert.equal(response.body.includes('private.invalid'), false);
  });
}

test('WS route must match the secret path exactly before upgrade', async t => {
  const f = await fixture(t);
  for (const url of [f.wsUrl.replace(f.config.pathToken,'wrong'), f.wsUrl+'?x=1', f.wsUrl+'/',
    f.wsUrl.replace('/wsHat','/api/admin/v1/state')]) assert.equal(await deniedUpgrade(url), 404);
  assert.equal(f.state.upgrades, 0);
});

test('invalid first frames never connect to upstream', async t => {
  const f = await fixture(t);
  const bad = [report, { act:'ca_login',device_id:'wrong' }, { act:'ca_login',device_id:Number(DEVICE_ID) },
    [], null, 'invalid json', Buffer.from(JSON.stringify(login))];
  for (const item of bad) {
    const ws = await connect(f.wsUrl), done = closed(ws);
    ws.send(Buffer.isBuffer(item) || typeof item === 'string' ? item : JSON.stringify(item));
    await done;
  }
  assert.equal(f.state.upgrades, 0);
});

test('unauthenticated idle socket expires without contacting upstream', async t => {
  const f = await fixture(t, { limits: { authTimeoutMs: 60 } });
  const ws = await connect(f.wsUrl);
  assert.equal(await closed(ws), 1008);
  assert.equal(f.state.upgrades, 0);
});

test('valid login and telemetry forward in order and canonicalize repeated JSON keys', async t => {
  const f = await fixture(t, { upgradeDelay: 30 });
  const ws = await connect(f.wsUrl);
  assert.equal(f.state.upgrades, 0);
  const raw = `{"act":"invalid","act":"ca_login","device_id":"${DEVICE_ID}"}`;
  const received = [];
  ws.on('message', value => received.push(JSON.parse(value.toString())));
  ws.send(raw); ws.send(JSON.stringify(report));
  await waitFor(() => received.length === 2);
  assert.deepEqual(f.state.messages, [login,report]);
  assert.equal((await exchange(ws, login)).status, true, 'Same-device login retry is supported');
  const done = closed(ws); ws.close(); await done;
  await waitFor(() => f.wss.clients.size === 0);
});

test('later identity switching is rejected before upstream receives it', async t => {
  const f = await fixture(t);
  const ws = await connect(f.wsUrl);
  await exchange(ws, login);
  const done = closed(ws); ws.send(JSON.stringify({ ...report,device_id:'other' })); await done;
  assert.deepEqual(f.state.messages, [login]);
  await waitFor(() => f.wss.clients.size === 0);
});

test('firmware local-record synchronization preserves login and subsequent telemetry', { timeout: 5000 }, async t => {
  const f = await fixture(t);
  // The current Java backend returns unsupported; that acknowledgement must
  // not turn this harmless firmware state report into a disconnected socket.
  f.state.localRecordAck = false;
  const ws = await connect(f.wsUrl);
  await exchange(ws, login);
  const expected = [login];
  for (const type of ['0', '1']) {
    // CapRequest has only reference fields with no constructor defaults; the
    // firmware's default Gson serializes just these three assigned fields.
    const sync = { act: 'toggle_localrecord', device_id: DEVICE_ID, type };
    assert.deepEqual(await exchange(ws, sync), { status: false, cmd: 'toggle_localrecord' });
    assert.equal((await exchange(ws, report)).status, true);
    expected.push(sync, report);
  }
  assert.equal(ws.readyState, WebSocket.OPEN);
  assert.deepEqual(f.state.messages, expected);
});

test('local-record synchronization cannot authenticate a socket', async t => {
  const f = await fixture(t);
  const ws = await connect(f.wsUrl), done = closed(ws);
  ws.send(JSON.stringify({ act: 'toggle_localrecord', device_id: DEVICE_ID, type: '1' }));
  assert.equal(await done, 1008);
  assert.equal(f.state.upgrades, 0);
  assert.deepEqual(f.state.messages, []);
});

test('local-record synchronization waits for successful upstream login', async t => {
  const f = await fixture(t, { upgradeDelay: 100 });
  const ws = await connect(f.wsUrl), done = closed(ws);
  ws.send(JSON.stringify(login));
  ws.send(JSON.stringify({ act: 'toggle_localrecord', device_id: DEVICE_ID, type: '1' }));
  assert.equal(await done, 1008);
  assert.deepEqual(f.state.messages, []);
});

test('local-record synchronization is rejected after a failed upstream login', async t => {
  const f = await fixture(t);
  f.state.loginAck = false;
  const ws = await connect(f.wsUrl);
  assert.equal((await exchange(ws, login)).status, false);
  const done = closed(ws);
  ws.send(JSON.stringify({ act: 'toggle_localrecord', device_id: DEVICE_ID, type: '1' }));
  assert.equal(await done, 1008);
  assert.deepEqual(f.state.messages, [login]);
});

for (const [label, changes] of [
  ['numeric type', { type: 1 }], ['other type', { type: '2' }], ['empty type', { type: '' }],
  ['null type', { type: null }], ['boolean type', { type: true }], ['object type', { type: {} }],
  ['missing type', { type: undefined }], ['wrong identity', { device_id: 'other' }],
  ['numeric identity', { device_id: Number(DEVICE_ID) }], ['missing identity', { device_id: undefined }],
  ['extra field', { record_switch: '1' }], ['unknown action', { act: 'toggle_unlisted' }],
]) {
  test(`local-record synchronization rejects ${label} before forwarding`, async t => {
    const f = await fixture(t);
    const ws = await connect(f.wsUrl);
    await exchange(ws, login);
    const done = closed(ws);
    ws.send(JSON.stringify({ act: 'toggle_localrecord', device_id: DEVICE_ID, type: '1', ...changes }));
    assert.equal(await done, 1008);
    assert.deepEqual(f.state.messages, [login]);
  });
}

test('upstream closure closes the client and releases the bridge', async t => {
  const f = await fixture(t);
  const ws = await connect(f.wsUrl); await exchange(ws, login);
  const done = closed(ws);
  for (const upstream of f.wss.clients) upstream.close();
  await done;
});

test('payload and pending queue bounds close overloaded connections', async t => {
  const f = await fixture(t, { upgradeDelay: 100, limits: { maxQueued: 80, maxPayload: 256 } });
  const ws = await connect(f.wsUrl), done = closed(ws);
  ws.send(JSON.stringify(login)); ws.send(JSON.stringify(report));
  assert.equal(await done, 1009);
  assert.equal(f.state.messages.length, 0);
  const next = await connect(f.wsUrl), oversized = closed(next);
  next.send('x'.repeat(300)); assert.equal(await oversized, 1009);
});

test('connection and message-rate caps are enforced without forwarding excess messages', async t => {
  const f = await fixture(t, { limits: { maxConnections: 1, messagesPerSecond: 2 } });
  const ws = await connect(f.wsUrl);
  assert.equal(await deniedUpgrade(f.wsUrl), 429);
  await exchange(ws, login); await exchange(ws, report);
  const done = closed(ws); ws.send(JSON.stringify(report)); assert.equal(await done, 1008);
  assert.equal(f.state.messages.length, 2);
});

test('gateway shutdown releases authenticated sockets on both sides', async t => {
  const f = await fixture(t);
  const ws = await connect(f.wsUrl); await exchange(ws, login);
  const done = closed(ws); await f.gateway.close(); await done;
  await waitFor(() => f.wss.clients.size === 0);
});

test('GPS diagnostics whitelist quality and coordinate flags without exact coordinates or identity', async t => {
  const rows = [];
  const f = await fixture(t, { onGpsReport: row => rows.push(row) });
  const ws = await connect(f.wsUrl); await exchange(ws, login);
  const first = { ...report, x_point: '35.123456789', y_point: '112.987654321', gps: '6', gps_level: '-1',
    c_accuracy: '125.5', c_startcount: '0', c_trust: '3', credential: f.config.pathToken };
  await exchange(ws, first);
  await exchange(ws, first);
  f.state.reportAck = false;
  await exchange(ws, { ...first, x_point: '35.223456789', c_trust: DEVICE_ID });
  await waitFor(() => rows.length === 3);
  assert.deepEqual(Object.keys(rows[0]).sort(), ['observedAt','gps','gps_level','c_accuracy','c_startcount','c_trust',
    'x','y','coordinatesChanged','upstreamAck','upstreamAckReceived'].sort());
  assert.deepEqual(rows[0].x, { present: true, finite: true, nonzero: true, inRange: true });
  assert.deepEqual(rows[0].y, rows[0].x);
  assert.equal(rows[0].gps, 6); assert.equal(rows[0].gps_level, -1); assert.equal(rows[0].c_accuracy, 125.5);
  assert.equal(rows[0].c_startcount, 0); assert.equal(rows[0].c_trust, 3);
  assert.match(rows[0].observedAt, /^\d{4}-\d{2}-\d{2}T.*Z$/);
  assert.deepEqual(rows.map(row => row.coordinatesChanged), [null, false, true]);
  assert.deepEqual(rows.map(row => row.upstreamAck), [true, true, false]);
  assert.ok(rows.every(row => row.upstreamAckReceived));
  assert.equal(rows[2].c_trust, null);
  const saved = JSON.stringify(rows);
  for (const secret of [DEVICE_ID, f.config.pathToken, first.x_point, first.y_point, '35.223456789', 'credential', 'device_id']) {
    assert.equal(saved.includes(secret), false);
  }
  assert.deepEqual(f.state.messages[1], first, 'Diagnostics do not change forwarded values');
});

test('GPS diagnostic cap is 12 across connections while all subsequent reports still forward', async t => {
  const rows = [];
  const f = await fixture(t, { onGpsReport: row => rows.push(row), limits: { messagesPerSecond: 40 } });
  const ws = await connect(f.wsUrl); await exchange(ws, login);
  for (let i = 0; i < 14; i++) assert.equal((await exchange(ws, report)).status, true);
  const next = await connect(f.wsUrl); await exchange(next, login); await exchange(next, report);
  assert.equal(rows.length, 12);
  assert.equal(f.state.messages.filter(message => message.act === 'ca_report_location').length, 15);
});

test('throwing or rejected diagnostic callbacks never disrupt real forwarding', async t => {
  for (const onGpsReport of [() => { throw new Error('private diagnostic failure'); },
    () => Promise.reject(new Error('private diagnostic failure'))]) {
    const f = await fixture(t, { onGpsReport });
    const ws = await connect(f.wsUrl); await exchange(ws, login);
    assert.equal((await exchange(ws, report)).status, true);
    assert.equal((await exchange(ws, report)).status, true);
    assert.deepEqual(f.state.messages, [login, report, report]);
  }
});

test('unattributed parser errors stop diagnostic ACK matching without interrupting forwarding', async t => {
  const rows = [];
  const f = await fixture(t, { onGpsReport: row => rows.push(row) });
  const ws = await connect(f.wsUrl); await exchange(ws, login);
  f.state.reportError = true; f.state.reportAck = false;
  assert.equal((await exchange(ws, report)).cmd, 'error');
  f.state.reportError = false; f.state.reportAck = true;
  assert.equal((await exchange(ws, report)).status, true);
  assert.equal(rows.length, 1);
  assert.equal(rows[0].upstreamAck, false); assert.equal(rows[0].upstreamAckReceived, false);
  assert.deepEqual(f.state.messages, [login, report, report]);
});

test('verified firmware photo upload gets acknowledgement only after durable cloud asset; headers cannot choose owner', async t => {
  let calls=0;
  const f=await fixture(t,{mediaFetch:async (url,options)=>{
    calls++; assert.match(url,new RegExp('deviceId='+DEVICE_ID+'&kind=photo$'));
    assert.ok(options.headers['X-Media-Signature']); assert.equal(options.headers['X-Device-Id'],undefined);
    return new Response(JSON.stringify({code:200,data:{deviceId:DEVICE_ID,kind:'photo',status:'ready',url:'https://helmet.example.com/helmet-media/files/asset?token=test'}}));
  }});
  const body=Buffer.from('--x\r\nContent-Disposition: form-data; name="file"; filename="a.jpg"\r\n\r\nimage\r\n--x--\r\n');
  const result=await fetch(f.origin+f.basePath+'?ctl=image&act=save_image',{method:'POST',body,headers:{'Content-Type':'multipart/form-data; boundary=x','X-Device-Id':'other'}});
  assert.equal(result.status,200); assert.equal((await result.json()).status,true); assert.equal(calls,1);
  const denied=await fetch(f.origin+f.basePath+'?ctl=image&act=save_image&device_id=other',{method:'POST',body,headers:{'Content-Type':'multipart/form-data; boundary=x'}});
  assert.equal(denied.status,400); assert.equal(calls,1);
});

test('failed media storage is not acknowledged as successful firmware upload',async t=>{
  const f=await fixture(t,{mediaFetch:async()=>new Response('{}',{status:503})});
  const r=await fetch(f.origin+f.basePath+'?ctl=image&act=save_image',{method:'POST',body:'--x--\r\n',headers:{'Content-Type':'multipart/form-data; boundary=x'}});
  assert.equal(r.status,502); assert.equal((await r.json()).status,false);
});

test('firmware push_to_client receipt is scoped to a previously sent talkback id',async t=>{
  const f=await fixture(t), client=await connect(f.wsUrl); await exchange(client,login);
  const delivered=once(client,'message');
  [...f.wss.clients][0].send(JSON.stringify({cmd:'server_push_get_local_video_list',talkback_id:'request1',start_time:'0',end_time:'1'}));
  await delivered;
  const receipt={act:'push_to_client',talkback_id:'request1',res:{status:true,msg:'获取成功',data:[{file_name:'clip.mp4',file_md5:'a'.repeat(32)}]}};
  assert.equal((await exchange(client,receipt)).cmd,'push_to_client');
  const closing=closed(client); client.send(JSON.stringify(receipt)); assert.equal(await closing,1008);
});

test('firmware video endpoint and photo binding are exact, scoped and require cloud success',async t=>{
 const paths=[];const f=await fixture(t,{mediaFetch:async(url,options)=>{
   paths.push(url);if(options.body?.[Symbol.asyncIterator])for await(const _ of options.body){}
   const binding=url.endsWith('/photo-bind');
   return new Response(JSON.stringify({code:200,data:binding?{status:'ready'}:{deviceId:DEVICE_ID,kind:'video',status:'ready',url:'https://helmet.example.com/helmet-media/files/video?token=x'}}));
 }});
 const upload=f.basePath.replace('index.php','upload')+'?device_id='+DEVICE_ID+'&X-Progress-ID=abc123xyz';
 const r=await fetch(f.origin+upload,{method:'POST',body:'--x--\r\n',headers:{'Content-Type':'multipart/form-data; boundary=x'}});
 assert.equal(r.status,200);assert.equal((await r.json()).status,true);assert.match(paths[0],/kind=video&progressId=abc123xyz$/);
 const bind=await fetch(f.origin+f.basePath+'?ctl=report&act=add_image',{method:'POST',body:JSON.stringify({device_id:DEVICE_ID,image_url:'https://helmet.example.com/helmet-media/files/photo',x_point:'22',y_point:'114'}),headers:{'Content-Type':'application/json'}});
 assert.equal(bind.status,200);assert.equal((await bind.json()).msg_code,'AddSucc');
 assert.equal((await fetch(f.origin+'/api/upload',{method:'POST'})).status,404);
});


test('offline collection timestamps are preserved and cannot impersonate another helmet',async t=>{
 const f=await fixture(t),endpoint=f.origin+f.basePath+'?ctl=lowcaps&act=ca_backup_data';
 const data='1792728000,22.1,114.2;1792728060,22.2,114.3;';
 const r=await fetch(endpoint,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({device_id:DEVICE_ID,data})});
 assert.equal(r.status,200);assert.equal((await r.json()).status,true);assert.deepEqual(f.state.lastBody,{device_id:DEVICE_ID,data});
 const denied=await fetch(endpoint,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({device_id:'other',data})});
 assert.equal(denied.status,400);assert.equal(f.state.requests,1);
});
