import { test } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { WebSocket } from 'ws';
import { createLab } from '../server.mjs';

async function fixture(t, options = {}) {
  const lab = createLab(options);
  await new Promise(resolve => lab.server.listen(0, '127.0.0.1', resolve));
  const base = `http://127.0.0.1:${lab.server.address().port}`;
  const sockets = [];
  t.after(async () => { sockets.forEach(s => s.terminate()); await lab.close(); });
  async function client(account, sn = '') {
    const ws = new WebSocket(base.replace('http:', 'ws:') + '/signal');
    const inbox = [], waiters = [];
    ws.on('message', raw => {
      const msg = JSON.parse(raw);
      const index = waiters.findIndex(w => w.match(msg));
      if (index >= 0) { const waiter = waiters.splice(index, 1)[0]; clearTimeout(waiter.timer); waiter.resolve(msg); }
      else inbox.push(msg);
    });
    const next = (match, timeout = 1500) => {
      const index = inbox.findIndex(match);
      if (index >= 0) return Promise.resolve(inbox.splice(index, 1)[0]);
      return new Promise((resolve, reject) => {
        const waiter = { match, resolve, timer: setTimeout(() => { waiters.splice(waiters.indexOf(waiter), 1); reject(new Error('Message timeout')); }, timeout) };
        waiters.push(waiter);
      });
    };
    sockets.push(ws);
    await new Promise(resolve => ws.on('open', resolve));
    const send = data => ws.send(JSON.stringify(data));
    send({ type: 'login', account, sn });
    const welcome = await next(m => m.type === 'welcome' || m.type === 'error');
    return { ws, next, send, welcome, inbox };
  }
  return { base, client };
}
const state = value => m => m.type === 'call' && m.call.state === value;
async function dial(a, b, extras = {}) {
  a.send({ type: 'dial', to: 'helmet-001', kind: 'video', transport: 'webrtc', ...extras });
  const { call } = await a.next(state('ringing'));
  await b.next(state('ringing'));
  return call;
}

test('accepting is not connected; both media reports are required; hangup frees accounts', async t => {
  const { client } = await fixture(t);
  const a = await client('dispatch'), b = await client('helmet-001');
  const call = await dial(a, b);
  b.send({ type: 'accept', callId: call.id });
  await a.next(state('connecting')); await b.next(state('connecting'));
  a.send({ type: 'media-state', callId: call.id, connected: true });
  a.send({ type: 'login', account: 'inspector' });
  assert.match((await a.next(m => m.type === 'error')).message, /结束当前通话/);
  assert.equal(a.inbox.some(state('connected')), false);
  b.send({ type: 'media-state', callId: call.id, connected: true });
  assert.ok((await a.next(state('connected'))).call.connectedAt);
  b.send({ type: 'end', callId: call.id });
  assert.equal((await a.next(state('ended'))).call.reason, 'hangup');
  a.send({ type: 'login', account: 'inspector' });
  assert.equal((await a.next(m => m.type === 'welcome')).account, 'inspector');
});

test('identity and SN cannot be occupied by two browser windows', async t => {
  const { client } = await fixture(t);
  await client('helmet-001', 'MH-DEMO-001');
  assert.equal((await client('helmet-001')).welcome.type, 'error');
  assert.match((await client('helmet-002', 'MH-DEMO-001')).welcome.message, /SN/);
});

test('offline, busy, and unconfigured Agora calls fail honestly', async t => {
  const { client } = await fixture(t);
  const a = await client('dispatch');
  a.send({ type: 'dial', to: 'helmet-001', kind: 'video', transport: 'webrtc' });
  assert.match((await a.next(m => m.type === 'error')).message, /不在线/);
  const b = await client('helmet-001');
  a.send({ type: 'dial', to: 'helmet-001', kind: 'video', transport: 'agora' });
  assert.match((await a.next(m => m.type === 'error')).message, /配置声网/);
  await dial(a, b);
  const c = await client('inspector');
  c.send({ type: 'dial', to: 'helmet-001', kind: 'audio', transport: 'webrtc' });
  assert.match((await c.next(m => m.type === 'error')).message, /通话中/);
});

test('third party cannot accept, relay media, or end another call', async t => {
  const { client } = await fixture(t);
  const a = await client('dispatch'), b = await client('helmet-001'), c = await client('inspector');
  const call = await dial(a, b);
  c.send({ type: 'end', callId: call.id });
  a.send({ type: 'accept', callId: call.id });
  b.send({ type: 'accept', callId: call.id });
  await a.next(state('connecting'));
  c.send({ type: 'signal', callId: call.id, data: { type: 'offer', sdp: 'bad' } });
  a.send({ type: 'signal', callId: call.id, data: { type: 'offer', sdp: 'valid' } });
  assert.equal((await b.next(m => m.type === 'signal')).data.sdp, 'valid');
  b.send({ type: 'end', callId: call.id });
  await a.next(state('ended'));
  assert.equal(a.inbox.some(m => m.type === 'call' && m.call.endedBy === 'inspector'), false);
});

test('reject, no-answer, connection timeout, and disconnect each terminate the call', async t => {
  const { client } = await fixture(t, { ringMs: 80, connectMs: 80 });
  const a = await client('dispatch'), b = await client('helmet-001');
  let call = await dial(a, b);
  b.send({ type: 'reject', callId: call.id });
  assert.equal((await a.next(state('ended'))).call.reason, 'rejected');
  await dial(a, b);
  assert.equal((await a.next(state('ended'))).call.reason, 'no_answer');
  call = await dial(a, b);
  b.send({ type: 'accept', callId: call.id });
  assert.equal((await a.next(state('ended'))).call.reason, 'connection_timeout');
  await dial(a, b);
  b.ws.close();
  assert.equal((await a.next(state('ended'))).call.reason, 'peer_left');
});

test('manufacturer bridge matches SN, issues separate tokens, and receives Android hangup', async t => {
  const { base, client } = await fixture(t, { appId: 'a'.repeat(32), appCertificate: 'b'.repeat(32) });
  const helmet = await client('helmet-001', 'MH-DEMO-001');
  const tokenResponse = await fetch(base + '/api/token').then(r => r.json());
  assert.equal(tokenResponse.data.expireTime, 7200);
  const response = await fetch(base + '/api/agora/token', { method: 'POST', body: JSON.stringify({ helmetSnList: ['MH-DEMO-001'] }) });
  const { data } = await response.json();
  assert.equal(response.status, 200); assert.equal(data.agoraUid, 1001); assert.match(data.agoraToken, /^007/);
  const { call } = await helmet.next(state('ringing'));
  assert.equal(call.external, true); assert.equal(call.transport, 'agora');
  assert.equal(JSON.stringify(call).includes(data.agoraToken), false);
  helmet.send({ type: 'accept', callId: call.id }); await helmet.next(state('connecting'));
  helmet.send({ type: 'credentials', callId: call.id });
  const credentials = (await helmet.next(m => m.type === 'credentials')).credentials;
  assert.equal(credentials.agoraUid, 1002); assert.equal(credentials.channelName, data.channelName);
  assert.notEqual(credentials.agoraToken, data.agoraToken);
  const config = await fetch(base + '/config').then(r => r.text());
  assert.equal(config.includes('b'.repeat(32)), false);
  await fetch(base + '/api/monitor/call/end', { method: 'POST', body: JSON.stringify({ channelName: data.channelName }) });
  assert.equal((await helmet.next(state('ended'))).call.reason, 'hangup');
});

test('manufacturer refuses fake credentials when Agora configuration is absent', async t => {
  const { base } = await fixture(t);
  const response = await fetch(base + '/api/agora/token', { method: 'POST', body: JSON.stringify({ helmetSnList: ['MH-DEMO-001'] }) });
  assert.equal(response.status, 400);
  assert.match((await response.json()).message, /尚未配置/);
});

test('Android API proxy preserves auth and synchronizes web rejection to the exact backend session', async t => {
  let labBase, resolveEnd;
  const ended = new Promise(resolve => { resolveEnd = resolve; });
  const backend = http.createServer(async (req, res) => {
    res.setHeader('Content-Type', 'application/json');
    if (req.url === '/api/v1/calls' && req.method === 'POST') {
      const vendor = await fetch(labBase + '/api/agora/token', { method: 'POST', body: JSON.stringify({ helmetSnList: ['MH-DEMO-001'] }) }).then(r => r.json());
      res.end(JSON.stringify({ code: 200, data: { id: '42', channelName: vendor.data.channelName, credentials: vendor.data } }));
    } else if (req.url === '/api/v1/calls/42/end') {
      resolveEnd({ authorization: req.headers.authorization, site: req.headers['x-site-id'] });
      res.end(JSON.stringify({ code: 200, data: { id: '42', status: 'ended' } }));
    } else { res.writeHead(404).end('{}'); }
  });
  await new Promise(resolve => backend.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => backend.close(resolve)));
  const lab = await fixture(t, { appId: 'a'.repeat(32), appCertificate: 'b'.repeat(32), backendUrl: `http://127.0.0.1:${backend.address().port}` });
  labBase = lab.base;
  const helmet = await lab.client('helmet-001', 'MH-DEMO-001');
  const response = await fetch(labBase + '/api/v1/calls', {
    method: 'POST', headers: { Authorization: 'Bearer test-session', 'X-Site-Id': 'site-a' }, body: '{}',
  }).then(r => r.json());
  assert.equal(response.data.id, '42');
  const { call } = await helmet.next(state('ringing'));
  helmet.send({ type: 'reject', callId: call.id });
  const termination = (await helmet.next(state('ended'))).call;
  assert.equal(JSON.stringify(termination).includes('test-session'), false);
  const headers = await Promise.race([ended, new Promise((_, reject) => { const timer = setTimeout(() => reject(new Error('Backend end missing')), 2000); timer.unref(); })]);
  assert.deepEqual(headers, { authorization: 'Bearer test-session', site: 'site-a' });
});
