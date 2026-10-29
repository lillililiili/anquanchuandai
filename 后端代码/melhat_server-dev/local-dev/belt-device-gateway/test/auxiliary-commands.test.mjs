import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { once } from 'node:events';
import { setTimeout as delay } from 'node:timers/promises';
import { WebSocket, WebSocketServer } from 'ws';
import { createBeltDeviceGateway } from '../gateway.mjs';
import { DEFAULTS, DEVICE_ID } from '../config.mjs';

const auxiliaryActions = ['getSettingWithDev', 'show_current_battery'];
const login = { act: 'ca_login', device_id: DEVICE_ID, type: 9 };
const report = { act: 'ca_report_location', imei: DEVICE_ID, timestamp: '1791510968',
  bat_l: '51', x_point: '0', y_point: '0' };

async function fixture(t, limits = {}) {
  const messages = [], events = [], sockets = new Set();
  const server = http.createServer((_request, response) => response.writeHead(404).end());
  const wss = new WebSocketServer({ noServer: true });
  server.on('connection', socket => { sockets.add(socket); socket.on('close', () => sockets.delete(socket)); });
  server.on('upgrade', (request, socket, head) => {
    assert.equal(request.url, '/wsBelt');
    wss.handleUpgrade(request, socket, head, ws => {
      ws.on('error', () => {});
      ws.on('message', raw => {
        const message = JSON.parse(raw.toString());
        messages.push(message);
        ws.send(JSON.stringify({ cmd: message.act, status: true }));
      });
    });
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  assert.notEqual(server.address().port, 18084, 'Never use the daily backend in this test');
  const config = { ...DEFAULTS, listenPort: 0, upstreamOrigin: `http://127.0.0.1:${server.address().port}`,
    publicOrigin: 'https://belt.example.com', pathToken: Buffer.alloc(32, 2).toString('base64url') };
  const gateway = createBeltDeviceGateway(config, { testOnly: true, limits: { closeTimeoutMs: 30, ...limits },
    observer: event => events.push(event) });
  const address = await gateway.listen();
  t.after(async () => {
    await gateway.close();
    for (const socket of sockets) socket.destroy();
    for (const ws of wss.clients) ws.terminate();
    await new Promise(resolve => wss.close(resolve));
    await new Promise(resolve => server.close(resolve));
  });
  async function connect() {
    const ws = new WebSocket(`ws://127.0.0.1:${address.port}/${config.pathToken}/wsBelt`);
    ws.on('error', () => {});
    await once(ws, 'open');
    return ws;
  }
  return { connect, messages, events };
}

async function exchange(ws, payload) {
  const received = once(ws, 'message');
  ws.send(JSON.stringify(payload));
  return JSON.parse((await received)[0].toString());
}
function closed(ws) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Isolated socket did not close')), 1800);
    ws.once('close', code => { clearTimeout(timer); resolve(code); });
  });
}

test('observed startup and battery actions leave the session open without ACK or upstream mutation', async t => {
  const f = await fixture(t), ws = await f.connect(), received = [];
  ws.on('message', raw => received.push(JSON.parse(raw.toString())));
  await exchange(ws, login);
  await exchange(ws, report);
  // Startup sequence proven at vendor log lines 53, 58, 60, 62. Battery action
  // is also present at line 1441; only protocol fields and synthetic data are used.
  for (const act of auxiliaryActions) ws.send(JSON.stringify({ act, device_id: DEVICE_ID, bat_l: '99' }));
  await delay(40);
  assert.equal(ws.readyState, WebSocket.OPEN);
  assert.equal(received.length, 2, 'Ignored actions must not fabricate responses');
  assert.deepEqual(f.messages, [login, report], 'Ignored actions must never reach telemetry storage');
  await exchange(ws, { ...report, bat_l: '50' });
  assert.equal(f.messages.length, 3, 'Normal telemetry must continue after ignored actions');
});

test('auxiliary actions cannot replace the first login or bypass fixed device identity', async t => {
  const f = await fixture(t);
  for (const act of auxiliaryActions) {
    const first = await f.connect(), firstClosed = closed(first);
    first.send(JSON.stringify({ act, device_id: DEVICE_ID }));
    assert.equal(await firstClosed, 1008);
    for (const identity of [{ device_id: 'wrong' }, { device_id: DEVICE_ID, imei: 'wrong' },
      { device_id: Number(DEVICE_ID) }, {}]) {
      const ws = await f.connect();
      await exchange(ws, login);
      const disconnected = closed(ws);
      ws.send(JSON.stringify({ act, ...identity }));
      assert.equal(await disconnected, 1008);
    }
  }
  assert.ok(f.messages.every(message => message.act === 'ca_login'));
});

test('ignored auxiliary traffic cannot keep an idle device online', async t => {
  const f = await fixture(t, { idleTimeoutMs: 180, messagesPerSecond: 100 });
  const ws = await f.connect();
  await exchange(ws, login);
  const disconnected = closed(ws);
  const timer = setInterval(() => {
    if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify({ act: 'getSettingWithDev', device_id: DEVICE_ID }));
  }, 30);
  try { assert.equal(await disconnected, 1001); }
  finally { clearInterval(timer); }
  assert.equal(f.messages.length, 1);
  assert.ok(f.events.some(event => event.event === 'ws_session' && event.reason === 'idle'));
});

test('ignored actions still obey the existing message rate limit', async t => {
  const f = await fixture(t, { messagesPerSecond: 3 });
  const ws = await f.connect();
  await exchange(ws, login);
  const disconnected = closed(ws);
  for (let count = 0; count < 4; count++) ws.send(JSON.stringify({ act: 'show_current_battery', device_id: DEVICE_ID }));
  assert.equal(await disconnected, 1008);
  assert.equal(f.messages.length, 1);
  assert.ok(f.events.some(event => event.event === 'ws_frame_rejected' && event.reason === 'rate'));
});
