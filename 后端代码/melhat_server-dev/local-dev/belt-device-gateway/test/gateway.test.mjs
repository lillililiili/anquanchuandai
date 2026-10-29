import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import net from 'node:net';
import { once } from 'node:events';
import { setTimeout as delay } from 'node:timers/promises';
import { WebSocket, WebSocketServer } from 'ws';
import { createBeltDeviceGateway } from '../gateway.mjs';
import { DEFAULTS, DEVICE_ID, validateConfig } from '../config.mjs';
import { EVENT_REASONS } from '../diagnostics.mjs';

const login = { act: 'ca_login', device_id: DEVICE_ID };
const report = { act: 'ca_report_location', imei: DEVICE_ID, bat_l: 51, is_weared: 1, hanger_a_status: '1', hanger_b_status: '0' };
// An explicit non-secret fixture credential. Never write a production config.
const TEST_PATH_CREDENTIAL = Buffer.alloc(32, 1).toString('base64url');

async function waitFor(check, timeout = 1500) {
  const deadline = Date.now() + timeout;
  while (!check()) { if (Date.now() > deadline) throw new Error('Timed out waiting for isolated fixture'); await delay(5); }
}
async function fixture(t, { limits = {}, mode = 'valid', upgradeDelay = 0, observer,
  wsReply = message => ({ status: true, cmd: message.act, act: message.act }) } = {}) {
  const state = { requests: 0, upgrades: 0, messages: [], requestUrls: [], mode };
  const sockets = new Set();
  const upstream = http.createServer((_request, response) => {
    assert.equal(_request.method, 'GET');
    assert.equal(new URL(_request.url, 'http://fixture.invalid').pathname, '/api/belt/index.php');
    state.requests++;
    state.requestUrls.push(_request.url);
    if (state.mode === 'hang') return;
    if (state.mode === 'redirect') { response.writeHead(302, { Location: 'http://127.0.0.1:18084/' }); response.end(); return; }
    if (state.mode === 'invalid') { response.end('invalid json'); return; }
    if (state.mode === 'oversize') { response.end('x'.repeat(70000)); return; }
    if (state.mode === 'failure') { response.writeHead(503); response.end(); return; }
    const payload = { status: true, msg: '获取成功', msg_code: 'GetSucc', data: { time: 1,
      config: JSON.stringify({ api_url: 'http://private.invalid/api/', ws_url: 'ws://private.invalid/wsBelt' }),
      extra: { watch_mac: '' } } };
    response.setHeader('Content-Type', 'application/json');
    response.end(JSON.stringify(payload));
  });
  upstream.on('connection', socket => { sockets.add(socket); socket.on('close', () => sockets.delete(socket)); });
  const wss = new WebSocketServer({ noServer: true });
  upstream.on('upgrade', (request, socket, head) => {
    assert.equal(request.url, '/wsBelt');
    state.upgrades++;
    if (state.mode === 'reject-ws') {
      socket.end('HTTP/1.1 503 Unavailable\r\nConnection: close\r\nContent-Length: 0\r\n\r\n');
      return;
    }
    const accept = () => {
      if (socket.destroyed) return;
      wss.handleUpgrade(request, socket, head, ws => {
        ws.on('error', () => {});
        ws.on('message', (raw, binary) => {
          assert.equal(binary, false);
          state.messages.push(JSON.parse(raw.toString()));
          ws.send(JSON.stringify(wsReply(state.messages.at(-1))));
        });
      });
    };
    if (upgradeDelay) setTimeout(accept, upgradeDelay); else accept();
  });
  upstream.listen(0, '127.0.0.1');
  await once(upstream, 'listening');
  const upstreamPort = upstream.address().port;
  assert.notEqual(upstreamPort, 18084, 'Fixture must never use the daily backend');
  const config = { ...DEFAULTS, listenPort: 0, pathToken: TEST_PATH_CREDENTIAL,
    upstreamOrigin: `http://127.0.0.1:${upstreamPort}`, publicOrigin: 'https://belt.example.com' };
  const gateway = createBeltDeviceGateway(config, { testOnly: true, limits: { closeTimeoutMs: 30, ...limits }, observer });
  const address = await gateway.listen();
  const origin = `http://127.0.0.1:${address.port}`;
  const basePath = `/${config.pathToken}/api/belt/index.php`;
  const query = `?ctl=config&act=get_config&device_id=${DEVICE_ID}`;
  const wsUrl = `ws://127.0.0.1:${address.port}/${config.pathToken}/wsBelt`;
  const deviceWsUrl = wsUrl.replace('/wsBelt', '/wsHat');
  const shortDeviceWsUrl = deviceWsUrl.replace(config.pathToken, config.pathToken.slice(0, 24));
  t.after(async () => {
    await gateway.close();
    for (const socket of sockets) socket.destroy();
    for (const ws of wss.clients) ws.terminate();
    await new Promise(resolve => wss.close(resolve));
    await new Promise(resolve => upstream.close(resolve));
  });
  return { gateway, config, state, wss, origin, basePath, query, wsUrl, deviceWsUrl, shortDeviceWsUrl };
}
function getRaw(f, path, options = {}) {
  return new Promise((resolve, reject) => {
    const request = http.request(f.origin, { path, method: options.method ?? 'GET', headers: options.headers }, response => {
      let body = '';
      response.setEncoding('utf8'); response.on('data', chunk => { body += chunk; });
      response.on('end', () => resolve({ status: response.statusCode, headers: response.headers, body }));
    });
    request.on('error', reject); request.end(options.body);
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
  const valid = { ...DEFAULTS, publicOrigin: 'https://belt.example.com', pathToken: TEST_PATH_CREDENTIAL };
  assert.equal(validateConfig(valid).deviceId, DEVICE_ID);
  for (const changed of [{ pathToken: '' }, { pathToken: 'a'.repeat(42) }, { publicOrigin: DEFAULTS.publicOrigin },
    { publicOrigin: 'http://belt.example.com' }, { publicOrigin: 'https://127.0.0.1' },
    { publicOrigin: 'https://[::1]' }, { publicOrigin: 'https://[2001:db8::1]' },
    { publicOrigin: 'https://[::ffff:7f00:1]' },
    { publicOrigin: 'https://belt.example.com/path' }, { listenHost: '0.0.0.0' },
    { upstreamOrigin: 'http://other.invalid' }, { publicWebSocketUrl: 'ws://other.invalid/wsHat' },
    { deviceId: 'other' }, { listenPort: 18086 }]) {
    assert.throws(() => validateConfig({ ...valid, ...changed }));
  }
  assert.throws(() => validateConfig(valid, { testOnly: true }), 'Test mode must reject the daily backend');
});

test('fallback config advertises vendor HTTP and protected WS independently of request Host', async t => {
  const f = await fixture(t);
  const response = await getRaw(f, f.basePath + f.query, { headers: { Host: 'attacker.invalid', 'X-Forwarded-Host': 'attacker.invalid' } });
  assert.equal(response.status, 200);
  const payload = JSON.parse(response.body), config = JSON.parse(payload.data.config);
  assert.equal(typeof payload.data.config, 'string');
  assert.equal(config.api_url, 'http://caps.runde.pro/api/');
  assert.equal(new URL('index.php', config.api_url).href, 'http://caps.runde.pro/api/index.php');
  assert.equal(config.ws_url, `ws://39.106.212.138:80/${f.config.pathToken.slice(0, 24)}/wsHat`);
  assert.equal(Object.hasOwn(payload.data, 'extra'), false);
  assert.equal(f.state.requests, 1);
  assert.deepEqual(f.state.requestUrls, ['/api/belt/index.php' + f.query],
    'Fallback configuration still comes from the fixed local upstream');
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

test('RD1102 boot POST accepts its sipphone flag with fixed UTF-8 response framing', async t => {
  const f = await fixture(t);
  const path = f.basePath + '?ctl=config&act=get_config';
  const form = new URLSearchParams({ device_id: DEVICE_ID,
    ca_ver: 'RD1102_V1_BEIDU_SVN10366_V1.2_20260121_1154', sipphone: '1' }).toString();
  const response = await getRaw(f, path, { method: 'POST', body: form,
    headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'Content-Length': Buffer.byteLength(form) } });
  assert.equal(response.status, 200);
  assert.equal(JSON.parse(response.body).status, true);
  assert.equal(response.headers['content-length'], String(Buffer.byteLength(response.body)));
  assert.equal(response.headers['transfer-encoding'], undefined);
  assert.deepEqual(f.state.requestUrls, ['/api/belt/index.php' + f.query]);
  assert.equal((await getRaw(f, f.basePath + f.query + '&sipphone=0')).status, 200);
  for (const flag of ['', '2', 'true', '01', '%00', '1&sipphone=1']) {
    assert.equal((await getRaw(f, f.basePath + f.query + '&sipphone=' + flag)).status, 400);
  }
  assert.equal((await getRaw(f, path + '&sipphone=1', { method: 'POST', body: form,
    headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'Content-Length': Buffer.byteLength(form) } })).status, 400);
  assert.equal(f.state.requests, 2, 'Invalid or duplicate metadata must not reach upstream');
});

test('manufacturer config/index.php alias preserves the same identity, parameter and method restrictions', async t => {
  const f = await fixture(t);
  const alias = f.basePath.replace('/index.php', '/config/index.php');
  for (const path of [f.basePath, alias]) {
    const response = await getRaw(f, path + f.query);
    assert.equal(response.status, 200);
    const config = JSON.parse(JSON.parse(response.body).data.config);
    assert.equal(config.api_url, 'http://caps.runde.pro/api/');
    assert.equal(config.ws_url, `ws://39.106.212.138:80/${f.config.pathToken.slice(0, 24)}/wsHat`);
    assert.equal((await getRaw(f, path + f.query, { method: 'POST' })).status, 200);
    assert.equal((await getRaw(f, path + f.query.replace(DEVICE_ID, 'wrong'))).status, 400);
    assert.equal((await getRaw(f, path + f.query + '&imei=wrong')).status, 400);
    assert.equal((await getRaw(f, path + f.query + '&device_id=' + DEVICE_ID)).status, 400);
    assert.equal((await getRaw(f, path + f.query + '&unlisted=x')).status, 400);
    assert.equal((await getRaw(f, path + f.query, { method: 'PUT' })).status, 405);
  }
  for (const path of [alias + '/', alias.replace('/config/', '/other/config/'),
    alias.replace('/config/', '/%63onfig/'), alias.replace(f.config.pathToken, 'wrong')]) {
    assert.equal((await getRaw(f, path + f.query)).status, 404);
  }
  assert.equal(f.state.requests, 4);
  for (const forwarded of f.state.requestUrls) assert.equal(forwarded, '/api/belt/index.php' + f.query);
});

test('unlisted paths, encoded paths, extra/duplicate query and wrong IDs never reach upstream', async t => {
  const f = await fixture(t);
  const denied = ['/api/admin/v1/state', '/api/guardian/v1/snapshot', '/wsBelt', '/wrong/api/belt/index.php',
    `${f.basePath}/`, `/${f.config.pathToken}/x/../api/belt/index.php`, `/${f.config.pathToken}/api/%69ndex.php`,
    f.basePath, f.basePath + f.query + '&unknown=x', f.basePath + f.query + '&device_id=' + DEVICE_ID,
    f.basePath + f.query.replace(DEVICE_ID, 'wrong'), f.basePath + f.query.replace('ctl', '%63tl'),
    f.basePath + f.query + '#fragment'];
  for (const path of denied) assert.ok((await getRaw(f, path)).status >= 400);
  assert.equal(f.state.requests, 0);
});

test('uploads fail explicitly and unsupported methods do not proxy', async t => {
  const f = await fixture(t);
  const response = await getRaw(f, f.basePath + '?ctl=file&act=upload', { method: 'POST' });
  assert.equal(response.status, 501);
  assert.deepEqual(JSON.parse(response.body), { status: false, msg_code: 'Unsupported', msg: 'Device request unavailable' });
  assert.equal((await getRaw(f, f.basePath + f.query, { method: 'PUT' })).status, 405);
  assert.equal(f.state.requests, 0);
});

test('GET and form POST accept the registered IMEI and canonicalize the upstream identity', async t => {
  const f = await fixture(t);
  const form = `ctl=config&act=get_config&imei=${DEVICE_ID}`;
  assert.equal((await getRaw(f, f.basePath + '?' + form)).status, 200);
  assert.equal((await getRaw(f, f.basePath + f.query + '&imei=' + DEVICE_ID)).status, 200);
  assert.equal((await getRaw(f, f.basePath + f.query, { method: 'POST' })).status, 200);
  assert.equal((await getRaw(f, f.basePath, { method: 'POST', body: form,
    headers: { 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8', 'Content-Length': Buffer.byteLength(form) } })).status, 200);
  const body = `imei=${DEVICE_ID}&ic=firmware`;
  assert.equal((await getRaw(f, f.basePath + '?ctl=config&act=get_config', { method: 'POST', body,
    headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'Content-Length': Buffer.byteLength(body) } })).status, 200);
  assert.equal(f.state.requests, 5);
  for (const url of f.state.requestUrls) {
    assert.equal(url, '/api/belt/index.php' + f.query);
  }
});

test('conflicting identities, duplicate query/body values and unbounded POST formats never proxy', async t => {
  const f = await fixture(t);
  for (const query of [f.query + '&imei=other', f.query.replace(DEVICE_ID, 'other') + '&imei=' + DEVICE_ID,
    '?ctl=config&act=get_config', f.query + '&imei=', f.query + '&imei=' + DEVICE_ID + '&imei=' + DEVICE_ID]) {
    assert.equal((await getRaw(f, f.basePath + query)).status, 400);
  }
  for (const [query, body, type] of [
    [f.query, `imei=other`, 'application/x-www-form-urlencoded'],
    [f.query, `device_id=${DEVICE_ID}`, 'application/x-www-form-urlencoded'],
    [f.query, '{}', 'application/json'],
    [f.query, 'x'.repeat(2049), 'application/x-www-form-urlencoded'],
    [f.query, 'ic=%FF', 'application/x-www-form-urlencoded'],
    [f.query, 'ic=x', 'multipart/form-data'],
  ]) {
    assert.equal((await getRaw(f, f.basePath + query, { method: 'POST', body,
      headers: { 'Content-Type': type, 'Content-Length': Buffer.byteLength(body) } })).status, 400);
  }
  assert.equal((await getRaw(f, f.basePath + f.query, { method: 'POST', body: 'ic=x',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'Transfer-Encoding': 'chunked' } })).status, 400);
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
  for (const route of [f.wsUrl, f.deviceWsUrl, f.shortDeviceWsUrl]) {
    const token = new URL(route).pathname.split('/')[1];
    for (const url of [route.replace(token,'wrong'), route+'?x=1', route+'/',
      route.replace('/'+token, ''), route.replace(token, '%'+token),
      route.replace(/\/ws(?:Belt|Hat)$/, '/api/admin/v1/state')]) {
      assert.equal(await deniedUpgrade(url), 404);
    }
  }
  assert.equal(f.state.upgrades, 0);
});

test('short credential authorizes only its exact wsHat route', async t => {
  const f = await fixture(t);
  const shortToken = f.config.pathToken.slice(0, 24);
  for (const url of [
    f.shortDeviceWsUrl.replace(shortToken, shortToken.slice(0, -1)),
    f.shortDeviceWsUrl.replace(shortToken, shortToken + 'x'),
    f.shortDeviceWsUrl.replace(shortToken, 'x' + shortToken.slice(1)),
    f.shortDeviceWsUrl.replace('/wsHat', '/wsBelt'),
  ]) assert.equal(await deniedUpgrade(url), 404);
  const shortBootstrap = f.basePath.replace(f.config.pathToken, shortToken);
  assert.equal((await getRaw(f, shortBootstrap + f.query)).status, 404);
  assert.equal((await getRaw(f, shortBootstrap.replace('/index.php', '/config/index.php') + f.query)).status, 404);
  assert.equal(f.state.requests, 0);
  assert.equal(f.state.upgrades, 0);
});

test('observed firmware handshake fits the 199-byte limit with the short route and upgrades', async t => {
  const f = await fixture(t);
  const request = token => `GET /${token}/wsHat HTTP/1.1\r\n`
    + 'Connection: Upgrade\r\nHost: 39.106.212.138:80\r\n'
    + 'Sec-WebSocket-Key: RkZGRkZGRkZGRkZGRkZGRg==\r\n'
    + 'Sec-WebSocket-Version: 13\r\nUpgrade: websocket\r\n\r\n';
  const longRequest = request(f.config.pathToken);
  assert.equal(Buffer.byteLength(longRequest), 205);
  assert.ok(longRequest.slice(0, 199).endsWith('Upgrade: websock'));
  const shortRequest = request(f.config.pathToken.slice(0, 24));
  assert.equal(Buffer.byteLength(shortRequest), 186);
  const socket = net.connect({ host: '127.0.0.1', port: Number(new URL(f.origin).port) });
  t.after(() => socket.destroy());
  await once(socket, 'connect');
  const firstResponse = once(socket, 'data');
  socket.write(shortRequest);
  const [response] = await firstResponse;
  assert.match(response.toString(), /^HTTP\/1\.1 101 Switching Protocols\r\n/);
  assert.equal(f.state.upgrades, 0, 'A handshake alone must not log in to the backend');
  socket.destroy();
});

test('short alias and original routes share one upgrade rate limit', async t => {
  const f = await fixture(t, { limits: { upgradesPerMinute: 2 } });
  for (const route of [f.shortDeviceWsUrl, f.deviceWsUrl]) {
    const ws = await connect(route);
    const done = closed(ws); ws.close(); await done;
  }
  assert.equal(await deniedUpgrade(f.wsUrl), 429);
  assert.equal(await deniedUpgrade(f.shortDeviceWsUrl), 429);
  assert.equal(f.state.upgrades, 0);
});

test('short alias expires without login and rejects identity changes after login', async t => {
  const f = await fixture(t, { limits: { authTimeoutMs: 80 } });
  const idle = await connect(f.shortDeviceWsUrl);
  assert.equal(await closed(idle), 1008);
  assert.equal(f.state.upgrades, 0);
  const ws = await connect(f.shortDeviceWsUrl);
  assert.equal((await exchange(ws, login)).status, true);
  const done = closed(ws);
  ws.send(JSON.stringify({ ...report, imei: 'wrong' }));
  assert.equal(await done, 1008);
  assert.deepEqual(f.state.messages, [login]);
});

test('invalid first frames never connect to upstream', async t => {
  const f = await fixture(t, { limits: { upgradesPerMinute: 40 } });
  const bad = [report, { act:'ca_login',device_id:'wrong' }, { act:'ca_login',device_id:Number(DEVICE_ID) },
    { act:'ca_login',imei:DEVICE_ID }, { ...login,imei:'wrong' },
    [], null, 'invalid json', Buffer.from(JSON.stringify(login))];
  for (const route of [f.wsUrl, f.deviceWsUrl, f.shortDeviceWsUrl]) {
    for (const item of bad) {
      const ws = await connect(route), done = closed(ws);
      ws.send(Buffer.isBuffer(item) || typeof item === 'string' ? item : JSON.stringify(item));
      await done;
    }
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

test('all protected WS paths reach only the belt upstream without requiring HTTP fallback', async t => {
  const f = await fixture(t, { mode: 'failure' });
  for (const route of [f.wsUrl, f.deviceWsUrl, f.shortDeviceWsUrl]) {
    const ws = await connect(route);
    assert.equal((await exchange(ws, login)).status, true);
    assert.equal((await exchange(ws, report)).status, true);
    const done = closed(ws); ws.close(); await done;
  }
  assert.deepEqual(f.state.messages, [login, report, login, report, login, report]);
  assert.equal(f.state.upgrades, 3, 'All aliases must use the fixture-checked /wsBelt upstream');
  assert.equal(f.state.requests, 0, 'WS must not depend on a local HTTP configuration request');
});

test('later identity switching is rejected before upstream receives it', async t => {
  const f = await fixture(t);
  const ws = await connect(f.deviceWsUrl);
  await exchange(ws, login);
  const done = closed(ws); ws.send(JSON.stringify({ ...report,device_id:'other' })); await done;
  assert.deepEqual(f.state.messages, [login]);
  await waitFor(() => f.wss.clients.size === 0);
});

test('both identity fields are checked on every authenticated belt frame', async t => {
  const f = await fixture(t);
  const ws = await connect(f.wsUrl);
  await exchange(ws, login);
  const both = { ...report, device_id: DEVICE_ID };
  await exchange(ws, both);
  const done = closed(ws);
  ws.send(JSON.stringify({ ...both, imei: 'other' }));
  assert.equal(await done, 1008);
  assert.deepEqual(f.state.messages, [login, both]);
  const next = await connect(f.wsUrl);
  await exchange(next, login);
  const rejected = closed(next);
  next.send(JSON.stringify({ ...report, imei: Number(DEVICE_ID) }));
  assert.equal(await rejected, 1008);
  assert.deepEqual(f.state.messages, [login, both, login]);
});

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
  assert.equal(await deniedUpgrade(f.deviceWsUrl), 429, 'Alias shares the same connection cap');
  assert.equal(await deniedUpgrade(f.shortDeviceWsUrl), 429, 'Short alias shares the same connection cap');
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

function assertPrivateObservations(events) {
  const counts = new Map();
  for (const item of events) {
    assert.deepEqual(Object.keys(item).sort(), ['count', 'event', 'reason', 'time']);
    assert.ok(EVENT_REASONS[item.event]?.includes(item.reason));
    assert.equal(new Date(item.time).toISOString(), item.time);
    const key = `${item.event}:${item.reason}`;
    assert.equal(item.count, (counts.get(key) ?? 0) + 1);
    counts.set(key, item.count);
    assert.ok(Object.isFrozen(item));
  }
  const output = JSON.stringify(events);
  for (const secret of [DEVICE_ID, TEST_PATH_CREDENTIAL, 'private.invalid', 'belt.example.com',
    'sensitive-query-marker', 'sensitive-body-marker', 'sensitive-coordinate-marker']) {
    assert.equal(output.includes(secret), false);
  }
}

function observationPairs(events) {
  return events.filter(item => item.event !== 'transport_connection').map(item => [item.event, item.reason]);
}

test('a TCP connection without protocol bytes is observed without inventing an HTTP or WS arrival', async t => {
  const events = [];
  const f = await fixture(t, { observer: item => events.push(item) });
  const socket = net.connect({ host: '127.0.0.1', port: Number(new URL(f.origin).port) });
  await once(socket, 'connect');
  await waitFor(() => events.length === 1);
  assert.deepEqual(events.map(item => [item.event, item.reason]), [['transport_connection', 'open']]);
  assert.equal(f.state.requests, 0);
  assert.equal(f.state.upgrades, 0);
  const done = once(socket, 'close'); socket.destroy(); await done;
  assertPrivateObservations(events);
});

test('HTTP observations distinguish arrivals, rejection categories and upstream outcome without request data', async t => {
  const events = [];
  const f = await fixture(t, { observer: item => events.push(item) });
  const cases = [
    ['/sensitive-query-marker', {}, 404, 'path'],
    [f.basePath + f.query, { method: 'PUT' }, 405, 'method'],
    [f.basePath + f.query + '&unlisted=sensitive-query-marker', {}, 400, 'parameters'],
    [f.basePath + '?ctl=config&act=sensitive-query-marker', {}, 400, 'action'],
    [f.basePath + '?ctl=config&act=get_config', {}, 400, 'identity_missing'],
    [f.basePath + f.query.replace(DEVICE_ID, 'sensitive-query-marker'), {}, 400, 'identity_mismatch'],
    [f.basePath, { method: 'POST', body: 'sensitive-body-marker', headers: {
      'Content-Type': 'application/json', 'Content-Length': 21,
    } }, 400, 'parameters'],
  ];
  for (const [path, options, status, reason] of cases) {
    const from = events.length;
    assert.equal((await getRaw(f, path, options)).status, status);
    assert.deepEqual(observationPairs(events.slice(from)),
      [['http_request', 'received'], ['http_result', reason]]);
  }
  assert.equal(f.state.requests, 0);
  assert.equal((await getRaw(f, f.basePath + f.query)).status, 200);
  assert.deepEqual(observationPairs(events.slice(-4)), [
    ['http_request', 'received'], ['http_upstream', 'connecting'], ['http_upstream', 'connected'], ['http_result', 'ok'],
  ]);
  f.state.mode = 'invalid';
  assert.equal((await getRaw(f, f.basePath + f.query)).status, 502);
  assert.deepEqual(observationPairs(events.slice(-2)),
    [['http_upstream', 'failed'], ['http_result', 'upstream_failure']]);
  assertPrivateObservations(events);
});

test('WS observations identify first-frame failure without accepting numeric, absent or conflicting identities', async t => {
  const events = [];
  const f = await fixture(t, { observer: item => events.push(item), limits: { upgradesPerMinute: 40 } });
  assert.equal(await deniedUpgrade(f.wsUrl.replace(f.config.pathToken, 'sensitive-query-marker')), 404);
  assert.deepEqual(observationPairs(events),
    [['ws_upgrade', 'received'], ['ws_upgrade_result', 'path']]);
  const cases = [
    ['sensitive-body-marker', 'json_invalid'], [[], 'shape_invalid'],
    [{ act: 'sensitive-body-marker' }, 'action_invalid'], [report, 'login_required'],
    [{ act: 'ca_login', imei: DEVICE_ID }, 'device_id_missing'],
    [{ ...login, device_id: Number(DEVICE_ID) }, 'device_id_type'],
    [{ ...login, device_id: 'sensitive-body-marker' }, 'device_id_mismatch'],
    [{ ...login, imei: Number(DEVICE_ID) }, 'imei_type'],
    [{ ...login, imei: 'sensitive-body-marker' }, 'imei_mismatch'],
    [Buffer.from(JSON.stringify(login)), 'binary'],
  ];
  for (const [payload, reason] of cases) {
    const from = events.length;
    const ws = await connect(f.wsUrl), done = closed(ws);
    ws.send(typeof payload === 'string' || Buffer.isBuffer(payload) ? payload : JSON.stringify(payload));
    assert.equal(await done, 1008);
    assert.deepEqual(observationPairs(events.slice(from)), [
      ['ws_upgrade', 'received'], ['ws_upgrade_result', 'accepted'],
      ['ws_first_frame', 'received'],
      ...(!['json_invalid', 'shape_invalid', 'binary'].includes(reason)
        ? [['ws_action_received', reason === 'action_invalid' ? 'unknown' : payload.act]] : []),
      ['ws_first_frame', reason],
    ]);
  }
  assert.equal(f.state.upgrades, 0);
  assertPrivateObservations(events);
});

test('login forwarding is observed only after the validated frame is sent to an open upstream', async t => {
  const events = [];
  const f = await fixture(t, { observer: item => events.push(item), upgradeDelay: 40 });
  const ws = await connect(f.wsUrl);
  const response = once(ws, 'message');
  ws.send(JSON.stringify({ ...login, latitude: 'sensitive-coordinate-marker' }));
  await waitFor(() => events.some(item => item.event === 'ws_upstream' && item.reason === 'connecting'));
  assert.equal(events.some(item => item.event === 'ws_login_forwarded'), false);
  await response;
  await waitFor(() => events.some(item => item.event === 'ws_login_forwarded'));
  assert.deepEqual(observationPairs(events), [
    ['ws_upgrade', 'received'], ['ws_upgrade_result', 'accepted'], ['ws_first_frame', 'received'],
    ['ws_action_received', 'ca_login'], ['ws_action_validated', 'ca_login'],
    ['ws_first_frame', 'accepted'], ['ws_upstream', 'connecting'], ['ws_upstream', 'connected'], ['ws_login_forwarded', 'ok'],
    ['ws_action_forwarded', 'ca_login'], ['ws_login_response', 'true'],
  ]);
  await exchange(ws, report);
  assert.equal(events.filter(item => item.event === 'ws_login_forwarded').length, 1);
  assertPrivateObservations(events);
});

test('failed upstream handshake and unauthenticated timeout remain distinct from forwarded login', async t => {
  const events = [];
  const f = await fixture(t, { observer: item => events.push(item), mode: 'reject-ws', limits: { authTimeoutMs: 80 } });
  const ws = await connect(f.wsUrl), done = closed(ws);
  ws.send(JSON.stringify(login));
  assert.equal(await done, 1011);
  assert.ok(events.some(item => item.event === 'ws_upstream' && item.reason === 'failed'));
  assert.equal(events.some(item => item.event === 'ws_login_forwarded'), false);
  const idle = await connect(f.wsUrl);
  assert.equal(await closed(idle), 1008);
  assert.ok(events.some(item => item.event === 'ws_first_frame' && item.reason === 'timeout'));
  assert.equal(f.state.upgrades, 1);
  assertPrivateObservations(events);
});

test('throwing or asynchronously rejecting observers cannot alter gateway acceptance', async t => {
  for (const observer of [() => { throw new Error('sensitive-body-marker'); },
    () => Promise.reject(new Error('sensitive-body-marker'))]) {
    const f = await fixture(t, { observer });
    assert.equal((await getRaw(f, f.basePath + f.query)).status, 200);
    const invalid = await connect(f.wsUrl), done = closed(invalid);
    invalid.send(JSON.stringify({ ...login, device_id: Number(DEVICE_ID) }));
    assert.equal(await done, 1008);
    assert.equal(f.state.upgrades, 0);
    const valid = await connect(f.wsUrl);
    assert.equal((await exchange(valid, login)).status, true);
    assert.deepEqual(f.state.messages, [login]);
  }
});

test('queued SOS and SIP SOS retain their action through receipt, validation, send and Java response', async t => {
  const events = [];
  const f = await fixture(t, { observer: item => events.push(item), upgradeDelay: 80 });
  const ws = await connect(f.wsUrl);
  const responses = [];
  ws.on('message', raw => responses.push(JSON.parse(raw.toString())));
  const messages = [login, { act: 'ca_sos', device_id: DEVICE_ID, type: 'sensitive-body-marker',
    latitude: 'sensitive-coordinate-marker', url: 'sensitive-query-marker' },
  { act: 'ca_sip_sos', imei: DEVICE_ID }, report];
  for (const message of messages) ws.send(JSON.stringify(message));
  await waitFor(() => events.filter(item => item.event === 'ws_action_validated').length === 4);
  assert.equal(events.some(item => item.event === 'ws_action_forwarded'), false,
    'Enqueueing does not count as a successful upstream send');
  await waitFor(() => responses.length === 4);
  assert.deepEqual(f.state.messages, messages, 'Diagnostics do not rewrite accepted frames');
  for (const event of ['ws_action_received', 'ws_action_validated', 'ws_action_forwarded']) {
    assert.deepEqual(events.filter(item => item.event === event).map(item => item.reason), messages.map(message => message.act));
  }
  for (const [act, responseEvent] of [['ca_login', 'ws_login_response'], ['ca_report_location', 'ws_location_response'],
    ['ca_sos', 'ws_sos_response'], ['ca_sip_sos', 'ws_sip_sos_response']]) {
    const received = events.findIndex(item => item.event === 'ws_action_received' && item.reason === act);
    const validated = events.findIndex(item => item.event === 'ws_action_validated' && item.reason === act);
    const forwarded = events.findIndex(item => item.event === 'ws_action_forwarded' && item.reason === act);
    const response = events.findIndex(item => item.event === responseEvent && item.reason === 'true');
    assert.ok(received < validated && validated < forwarded && forwarded < response);
  }
  assertPrivateObservations(events);
});

test('SOS failure responses and invalid status values are observed without claiming success or altering ACKs', async t => {
  const events = [];
  let status = false;
  const f = await fixture(t, { observer: item => events.push(item), wsReply: message => ({ cmd: message.act,
    status: message.act === 'ca_login' ? true : status, msg: 'sensitive-body-marker' }) });
  const ws = await connect(f.wsUrl);
  await exchange(ws, login);
  for (const nextStatus of [false, 'true', 1, null]) {
    status = nextStatus;
    for (const [act, event] of [['ca_sos', 'ws_sos_response'], ['ca_sip_sos', 'ws_sip_sos_response']]) {
      const response = await exchange(ws, { act });
      assert.deepEqual(response, { cmd: act, status, msg: 'sensitive-body-marker' });
      assert.equal(events.filter(item => item.event === event).at(-1).reason, status === false ? 'false' : 'invalid');
    }
  }
  assert.equal(events.some(item => ['ws_sos_response', 'ws_sip_sos_response'].includes(item.event) && item.reason === 'true'), false);
  assert.equal(ws.readyState, WebSocket.OPEN);
  assertPrivateObservations(events);
});

test('an unknown action is counted only as unknown; invalid SOS identity never reaches validated or forwarded stages', async t => {
  const events = [];
  const f = await fixture(t, { observer: item => events.push(item) });
  for (const payload of [{ act: 'sensitive-body-marker', device_id: DEVICE_ID },
    { act: 'ca_sos', device_id: 'sensitive-body-marker' }]) {
    const ws = await connect(f.wsUrl);
    await exchange(ws, login);
    const done = closed(ws);
    ws.send(JSON.stringify(payload));
    assert.equal(await done, 1008);
  }
  assert.equal(events.filter(item => item.event === 'ws_action_received' && item.reason === 'unknown').length, 1);
  assert.equal(events.filter(item => item.event === 'ws_action_received' && item.reason === 'ca_sos').length, 1);
  assert.equal(events.some(item => ['ws_action_validated', 'ws_action_forwarded'].includes(item.event) && item.reason !== 'ca_login'), false);
  assert.deepEqual(f.state.messages, [login, login]);
  assertPrivateObservations(events);
});

test('a failed upstream send callback never counts SOS as forwarded', async t => {
  const events = [];
  const f = await fixture(t, { observer: item => events.push(item) });
  const originalSend = WebSocket.prototype.send;
  t.mock.method(WebSocket.prototype, 'send', function(data, options, callback) {
    if (this.url === `${f.config.upstreamOrigin.replace(/^http:/, 'ws:')}/wsBelt`
        && JSON.parse(data.toString()).act === 'ca_sos') {
      queueMicrotask(() => callback(new Error('sensitive-body-marker')));
      return;
    }
    return originalSend.call(this, data, options, callback);
  });
  const ws = await connect(f.wsUrl);
  await exchange(ws, login);
  const done = closed(ws);
  ws.send(JSON.stringify({ act: 'ca_sos' }));
  assert.equal(await done, 1011);
  assert.ok(events.some(item => item.event === 'ws_action_validated' && item.reason === 'ca_sos'));
  assert.ok(events.some(item => item.event === 'ws_session' && item.reason === 'send_failed'));
  assert.equal(events.some(item => item.event === 'ws_action_forwarded' && item.reason === 'ca_sos'), false);
  assert.deepEqual(f.state.messages, [login]);
  assertPrivateObservations(events);
});

test('unrecognized and malformed upstream replies remain byte-for-byte transparent and do not affect the next report', async t => {
  const events = [];
  const f = await fixture(t, { observer: item => events.push(item) });
  const ws = await connect(f.wsUrl);
  await exchange(ws, login);
  const replies = [
    [' {"cmd":"ca_sos","status":false,"msg":"sensitive-body-marker"} ', 'ws_sos_response', 'false'],
    ['{"cmd":"ca_sip_sos","status":"true"}', 'ws_sip_sos_response', 'invalid'],
    ['{"cmd":"error","status":false,"msg":"sensitive-body-marker"}', 'ws_error_response', 'false'],
    ['{"cmd":"sensitive-body-marker","status":true}', 'ws_response_invalid', 'cmd_unknown'],
    ['{"cmd":{"private":"sensitive-body-marker"}}', 'ws_response_invalid', 'cmd_unknown'],
    ['{"cmd":"toString","status":true}', 'ws_response_invalid', 'cmd_unknown'],
    ['["sensitive-body-marker"]', 'ws_response_invalid', 'shape_invalid'],
    ['sensitive-body-marker', 'ws_response_invalid', 'json_invalid'],
  ];
  for (const [raw, event, reason] of replies) {
    const received = once(ws, 'message');
    for (const upstream of f.wss.clients) upstream.send(raw);
    const [forwarded, binary] = await received;
    assert.equal(forwarded.toString(), raw);
    assert.equal(binary, false);
    assert.equal(events.at(-1).event, event);
    assert.equal(events.at(-1).reason, reason);
  }
  assert.equal((await exchange(ws, report)).status, true);
  assert.deepEqual(f.state.messages, [login, report]);
  assertPrivateObservations(events);
});
