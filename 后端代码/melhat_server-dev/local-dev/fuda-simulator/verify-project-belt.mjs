// Actual project WebSocket -> SQL -> push -> simulator; synthetic belt only.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
import {createHash, createHmac, randomUUID} from 'node:crypto';
const root = path.dirname(fileURLToPath(import.meta.url)), local = path.join(root, '.local/integration');
const cfg = JSON.parse(fs.readFileSync(path.join(local, 'java-config.json')));
const sim = JSON.parse(fs.readFileSync(path.join(root, '.local/config.json')));
assert.equal(cfg.javaOrigin, 'http://127.0.0.1:18095');
const deviceId = 'FUDA-IT-BELT-01', result = {deviceId, synthetic: true, checks: []};
async function post(route, input, headers = {}) {
  const response = await fetch(cfg.javaOrigin + route, {method: 'POST', headers: {'Content-Type': 'application/json', ...headers}, body: JSON.stringify(input)});
  const body = await response.json(); assert(response.ok, `HTTP ${response.status} ${body.errorCode || body.code}`); return body;
}
const state = async () => (await (await fetch('http://127.0.0.1:19091/api/state')).json()).data.events.map(row => row.event);
async function until(fn, label) {
  const deadline = Date.now() + 30000;
  while (Date.now() < deadline) {if (await fn()) return; await new Promise(resolve => setTimeout(resolve, 200));}
  throw Error('Timed out: ' + label);
}
function sign(route, input) {
  const time = String(Math.floor(Date.now()/1000)), nonce = randomUUID();
  const hash = createHash('sha256').update(JSON.stringify(input)).digest('hex');
  const signature = createHmac('sha256', Buffer.from(sim.secretBase64, 'base64')).update(`POST\n${route}\n${sim.appId}\n${time}\n${nonce}\n${hash}`).digest('hex');
  return {'X-App-Id': sim.appId, 'X-Timestamp': time, 'X-Nonce': nonce, 'X-Signature': signature};
}
const auth = await post('/api/admin/v1/login', {username: cfg.adminUsername, password: cfg.adminPassword});
const registered = await post('/api/admin/v1/execute', {type: 'devices.create', input: {siteId: 'site-1', operationId: 'fuda-local-integration-register-belt',
  data: {type: 'BELT', source: 'DIRECT_BELT', deviceNumber: deviceId, code: deviceId, sn: 'FUDA-IT-BELT-SERIAL', name: 'Local integration belt', manufacturer: 'Local fixture'}}}, {'X-Wearable-Token': auth.token});
assert.equal(registered.data.id, 'device-1002');
await post('/api/admin/v1/logout', {}, {'X-Wearable-Token': auth.token});
const socket = new WebSocket('ws://127.0.0.1:18095/wsBelt');
socket.addEventListener('error', () => {});
await new Promise((resolve, reject) => {socket.addEventListener('open', resolve, {once: true}); socket.addEventListener('error', reject, {once: true});});
function send(input) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {socket.removeEventListener('message', listener); reject(Error('Belt response timeout'));}, 10000);
    const listener = ({data}) => {const body = JSON.parse(data); if (body.cmd !== input.act) return;
      clearTimeout(timer); socket.removeEventListener('message', listener); resolve(body);};
    socket.addEventListener('message', listener); socket.send(JSON.stringify(input));
  });
}
try {
  assert.equal((await send({act: 'ca_login', device_id: deviceId})).status, true);
  const before = new Set((await state()).map(row => row.eventId));
  assert.equal((await send({act: 'ca_report_location', imei: deviceId, bat_l: 73, is_weared: 0, hanger_a_status: 0, hanger_b_status: 0,
    x_point: 36.51, y_point: 118.51, gps: '1'})).status, true);
  assert.equal((await send({act: 'ca_sos', device_id: deviceId, type: '6', timestamp: String(Math.floor(Date.now()/1000))})).status, true);
  let received;
  await until(async () => {
    received = (await state()).filter(row => row.data.deviceId === deviceId && !before.has(row.eventId));
    return ['POSITION', 'STATUS', 'ALARM'].every(type => received.some(row => row.eventType === type));
  }, 'three belt event types received');
  assert(received.every(row => row.data.deviceType === 'SAFETY_BELT'));
  const status = received.find(row => row.eventType === 'STATUS' && row.trigger === 'REPORT').data;
  assert.equal(status.battery.percent, 73);
  assert.equal(received.find(row => row.eventType === 'POSITION').data.position.coordinateSystem, 'WGS84');
  result.checks.push('Belt login, position/status/alarm reports delivered through project sender');
  for (const kind of ['positions', 'statuses', 'alarms']) {
    const route = `/openapi/wearables/v2/${kind}/query`;
    const input = kind === 'alarms' ? {cursor: null, limit: 100} : {devices: [{deviceType: 'SAFETY_BELT', deviceId}]};
    const query = await post(route, input, sign(route, input)); assert.equal(query.code, 0);
    assert(query.data.items.some(row => row.deviceId === deviceId));
  }
  result.checks.push('All three original query APIs include the belt'); result.completed = true;
  result.eventIds = received.map(row => row.eventId);
} finally {socket.close(); fs.writeFileSync(path.join(local, 'belt-result.json'), JSON.stringify(result, null, 2));}
console.log(JSON.stringify({completed: result.completed, checks: result.checks}));
