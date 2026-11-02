// A loopback-only fixture drives the actual project WebSocket/HTTP/SQL path.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash, createHmac, randomUUID} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {createVideoSource} from './video-source.mjs';

const root = path.dirname(fileURLToPath(import.meta.url));
const local = path.join(root, '.local/integration');
const cfg = JSON.parse(fs.readFileSync(path.join(local, 'java-config.json')));
const sim = JSON.parse(fs.readFileSync(path.join(root, '.local/config.json')));
assert.equal(cfg.javaOrigin, 'http://127.0.0.1:18095');
assert.equal(cfg.deviceId, 'FUDA-IT-HELMET-01');
const evidence = {checks: [], source: 'actual project JAR and isolated MySQL, synthetic device over WebSocket'};
const messages = [], pending = new Map();
let socket, stopping = false, connected = false, mode = 'normal', retryTimer, heartbeat, running = false;
const media = createVideoSource({onEvent: event => messages.push({at: new Date().toISOString(), media: event})});
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const save = () => fs.writeFileSync(path.join(local, 'data-result.json'), JSON.stringify(evidence, null, 2));
async function until(predicate, label, timeout = 30000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) { if (await predicate()) return; await delay(200); }
  throw Error('Timed out: ' + label);
}
function sql(statement) {
  return execFileSync('docker', ['exec', '-i', 'fuda-sim-it-mysql', 'sh', '-c',
    'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot -N -B --raw fuda_sim_it'],
    {input: statement, encoding: 'utf8', windowsHide: true}).trim();
}
function rows() {
  return sql("SELECT JSON_OBJECT('id',event_id,'type',event_type,'status',status,'attempts',attempts,'body',body) FROM fuda_push_outbox ORDER BY sequence;")
    .split('\n').filter(Boolean).map(line => {const row = JSON.parse(line); row.body = JSON.parse(row.body); return row;});
}
async function json(url, input, headers = {}) {
  const response = await fetch(url, {method: input === undefined ? 'GET' : 'POST', headers: {'Content-Type': 'application/json', ...headers},
    ...(input === undefined ? {} : {body: JSON.stringify(input)}), signal: AbortSignal.timeout(20000)});
  const body = await response.json();
  assert(response.ok, `HTTP ${response.status} at ${new URL(url).pathname}: ${body.errorCode || body.code || ''}`);
  return body;
}
const simulator = () => json('http://127.0.0.1:19091/api/state');
function signed(route, body) {
  const time = String(Math.floor(Date.now()/1000)), nonce = randomUUID();
  const digest = createHash('sha256').update(body).digest('hex');
  const signature = createHmac('sha256', Buffer.from(sim.secretBase64, 'base64'))
    .update(`POST\n${route}\n${sim.appId}\n${time}\n${nonce}\n${digest}`).digest('hex');
  return {'Content-Type': 'application/json', 'X-App-Id': sim.appId, 'X-Timestamp': time, 'X-Nonce': nonce, 'X-Signature': signature};
}
async function query(kind, input) {
  const route = `/openapi/wearables/v2/${kind}/query`, body = JSON.stringify(input);
  const response = await fetch(cfg.javaOrigin + route, {method: 'POST', headers: signed(route, body), body});
  const result = await response.json(); assert.equal(result.code, 0, `${kind} query code ${result.code}`); return result.data;
}
async function register() {
  const auth = await json(cfg.javaOrigin + '/api/admin/v1/login', {username: cfg.adminUsername, password: cfg.adminPassword});
  const result = await json(cfg.javaOrigin + '/api/admin/v1/execute', {type: 'devices.create', input: {
    siteId: 'site-1', operationId: 'fuda-local-integration-register-helmet', data: {type: 'HELMET', source: 'DIRECT_HELMET',
      deviceNumber: cfg.deviceId, code: cfg.deviceId, sn: 'FUDA-IT-SERIAL-01', manufacturer: 'Local integration fixture', name: 'Local integration helmet'}}},
    {'X-Wearable-Token': auth.token});
  assert.equal(result.data.id, cfg.ledgerId);
  await json(cfg.javaOrigin + '/api/admin/v1/logout', {}, {'X-Wearable-Token': auth.token});
}
function send(input) {
  assert.equal(socket?.readyState, WebSocket.OPEN, 'Device socket must be connected');
  return new Promise((resolve, reject) => {
    const queue = pending.get(input.act) || [];
    const waiter = {resolve, reject, timer: setTimeout(() => {pending.set(input.act, queue.filter(x => x !== waiter)); reject(Error('Device response timeout: ' + input.act));}, 12000)};
    queue.push(waiter); pending.set(input.act, queue); socket.send(JSON.stringify(input));
  });
}
function connect() {
  socket = new WebSocket(cfg.javaOrigin.replace('http:', 'ws:') + '/wsHat');
  socket.addEventListener('open', async () => {
    try {const login = await send({act: 'ca_login', device_id: cfg.deviceId}); assert.equal(login.status, true); connected = true;}
    catch {socket.close();}
  });
  socket.addEventListener('message', ({data}) => {
    const body = JSON.parse(data);
    if (body.cmd?.startsWith('server_push_')) {media.command(body); return;}
    const item = pending.get(body.cmd)?.shift();
    if (item) {clearTimeout(item.timer); item.resolve(body);}
  });
  socket.addEventListener('error', () => {});
  socket.addEventListener('close', () => {
    connected = false; media.stop();
    for (const queue of pending.values()) for (const item of queue) {clearTimeout(item.timer); item.reject(Error('Device disconnected'));}
    pending.clear();
    if (!stopping) retryTimer = setTimeout(connect, 2000);
  });
}
async function report(battery = 86, position = true) {
  const response = await send({act: 'ca_report_location', device_id: cfg.deviceId, bat_l: battery, is_weared: 2,
    ...(position ? {x_point: 36.5, y_point: 118.5, gps: '1', app_version: 'LOCAL-IT-1'} : {})});
  assert.equal(response.status, true, 'Project must confirm device report persistence');
}
async function delivered() {await until(() => rows().every(row => row.status === 'DELIVERED'), 'outbox fully delivered');}
function passed(name) {evidence.checks.push({name, passed: true, at: new Date().toISOString()}); save();}

async function tests() {
  assert(!running, 'Test already running'); running = true; clearInterval(heartbeat);
  try {
    await until(() => connected, 'device login'); await delivered();
    const before = new Set(rows().map(x => x.id));
    await report(86); await delivered();
    let added = rows().filter(x => !before.has(x.id));
    assert(added.some(x => x.type === 'POSITION' && x.body.data.position?.coordinateSystem === 'WGS84'));
    assert(added.some(x => x.type === 'STATUS' && x.body.data.battery?.percent === 86));
    assert.equal((await send({act: 'ca_sos', device_id: cfg.deviceId, type: '77'})).status, true);
    await delivered();
    const alarm = rows().findLast(x => x.type === 'ALARM'); assert(alarm);
    assert((await simulator()).data.events.some(x => x.event.eventId === alarm.id));
    passed('Device WebSocket -> committed business/outbox -> signed HTTP -> simulator: position/status/alarm');

    const beforeDrop = new Set(rows().map(x => x.id)), duplicateBefore = (await simulator()).data.duplicates;
    mode = 'drop-response-once'; await report(85, false); await delivered();
    added = rows().filter(x => !beforeDrop.has(x.id)); assert(added.some(x => x.attempts >= 2));
    assert((await simulator()).data.duplicates > duplicateBefore);
    passed('Receiver saved but response lost: project retry preserves eventId; receiver deduplicates');

    const beforeFail = new Set(rows().map(x => x.id)); mode = 'unavailable'; await report(84, false);
    await until(() => rows().some(x => !beforeFail.has(x.id) && x.attempts > 0 && x.status !== 'DELIVERED'), '503 persisted retry');
    mode = 'normal'; await delivered();
    passed('Receiver 503: task remains pending, then automatically recovers');

    const device = {devices: [{deviceType: 'HELMET', deviceId: cfg.deviceId}]};
    const positions = await query('positions', device), statuses = await query('statuses', device);
    assert.equal(positions.items[0].position.coordinateSystem, 'WGS84');
    assert.equal(statuses.items[0].battery.percent, 84);
    const alarms = await query('alarms', {cursor: null, limit: 100});
    assert(alarms.items.some(x => x.eventId === alarm.body.data.eventId));
    passed('Existing signed query APIs remain usable; alarm business ID matches push');

    const beforeDisconnect = rows().length; socket.close();
    await until(() => !connected, 'device socket closed');
    await until(() => rows().slice(beforeDisconnect).some(x => x.body.trigger === 'OFFLINE'), 'offline event');
    await until(() => connected && rows().slice(beforeDisconnect).some(x => x.body.trigger === 'ONLINE'), 'device reconnect and online projection');
    await delivered();
    passed('Device disconnect/reconnect emits offline/online events');
    evidence.outbox = rows().map(({id, type, status, attempts}) => ({id, type, status, attempts}));
    evidence.receiver = (await simulator()).data.counts; evidence.completed = true; save();
    return evidence;
  } finally {mode = 'normal'; running = false; startHeartbeat();}
}
function startHeartbeat() {
  clearInterval(heartbeat);
  heartbeat = setInterval(() => {if (connected && !running) report(84, false).catch(() => {});}, 20000);
}

const relay = http.createServer(async (req, res) => {
  if (req.headers.host !== '127.0.0.1:19092' || req.method !== 'POST' || req.url !== '/receive') {res.writeHead(404).end(); return;}
  if (mode === 'unavailable') {res.writeHead(503, {'content-type': 'application/json', 'retry-after': '1'}).end('{"code":503}'); return;}
  const upstream = http.request({hostname: '127.0.0.1', port: 19091, path: '/receive', method: 'POST',
    headers: {...req.headers, host: '127.0.0.1:19091'}}, reply => {
    if (mode === 'drop-response-once') {mode = 'normal'; reply.resume(); reply.on('end', () => res.destroy()); return;}
    res.writeHead(reply.statusCode, reply.headers); reply.pipe(res);
  });
  upstream.setTimeout(10000, () => upstream.destroy());
  upstream.on('error', () => {if (!res.headersSent) res.writeHead(503); res.end();}); req.pipe(upstream);
});
const control = http.createServer(async (req, res) => {
  const reply = (code, value) => {res.writeHead(code, {'content-type': 'application/json'}); res.end(JSON.stringify(value));};
  if (req.headers.host !== '127.0.0.1:19101' || req.headers.origin && req.headers.origin !== 'http://127.0.0.1:19101') return reply(403, {error: 'loopback only'});
  if (req.method === 'GET' && req.url === '/api/state') return reply(200, {connected, mode, running, media: media.snapshot(), checks: evidence.checks});
  if (req.method !== 'POST' || req.headers['x-integration-request'] !== '1') return reply(403, {error: 'local control only'});
  try {
    if (req.url === '/api/test-data') return reply(200, await tests());
    if (req.url === '/api/queue-before-restart') {
      await until(() => connected, 'device connected before queuing');
      clearInterval(heartbeat); mode = 'unavailable'; const ids = new Set(rows().map(x => x.id)); await report(83, false);
      await until(() => rows().some(x => !ids.has(x.id) && x.attempts > 0), 'pending event before restart');
      evidence.pendingBeforeRestart = rows().filter(x => !ids.has(x.id)).map(x => x.id); save(); return reply(200, {queued: evidence.pendingBeforeRestart.length});
    }
    if (req.url === '/api/resume-after-restart') {
      mode = 'normal'; await until(() => connected, 'reconnect after project restart'); await delivered();
      assert(evidence.pendingBeforeRestart?.every(id => rows().some(x => x.id === id && x.status === 'DELIVERED')));
      passed('Actual project process restart: committed pending event recovered with original eventId'); startHeartbeat();
      return reply(200, {recovered: evidence.pendingBeforeRestart.length});
    }
    return reply(404, {error: 'route'});
  } catch (error) {evidence.lastError = error.message; save(); reply(500, {error: error.message});}
});
await new Promise((resolve, reject) => {relay.once('error', reject); relay.listen(19092, '127.0.0.1', resolve);});
await new Promise((resolve, reject) => {control.once('error', reject); control.listen(19101, '127.0.0.1', resolve);});
await until(async () => {try {await register(); return true;} catch {return false;}}, 'project startup and device registration', 120000);
connect(); startHeartbeat();
console.log('Local project fixture ready: relay 19092, control 19101. No production configuration loaded.');
async function close() {stopping = true; clearInterval(heartbeat); clearTimeout(retryTimer); socket?.close(); media.stop(); relay.close(); control.close();}
process.on('SIGINT', close); process.on('SIGTERM', close);
