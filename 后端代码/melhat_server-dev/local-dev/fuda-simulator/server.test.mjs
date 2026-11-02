import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import http from 'node:http';
import { startSimulator } from './server.mjs';

async function fixture(t) {
  const directory = await mkdtemp(join(tmpdir(), 'fuda-simulator-'));
  const app = await startSimulator({ directory, httpPort: 0, sipPort: 0, ffmpegPath: process.env.FFMPEG_PATH });
  t.after(async () => { await app.close(); await rm(directory, { recursive: true, force: true }); });
  return app;
}
const post = (body = {}) => ({ method: 'POST', headers: { 'content-type': 'application/json', 'x-simulator-request': '1' }, body: JSON.stringify(body) });
async function until(fn, timeout = 12000) {
  const end = Date.now() + timeout;
  while (Date.now() < end) { const value = await fn(); if (value) return value; await new Promise(r => setTimeout(r, 40)); }
  throw Error('Expected simulator state did not arrive');
}
test('dashboard accepts signed samples of all three types and persists them', async t => {
  const app = await fixture(t);
  const response = await fetch(app.url + '/api/demo/data', post());
  assert.equal(response.status, 200);
  const state = await (await fetch(app.url + '/api/state')).json();
  assert.equal(state.data.total, 3);
  assert.deepEqual(state.data.counts, { POSITION: 1, STATUS: 1, ALARM: 1 });
  assert.equal(state.data.events.length, 3);
  assert.equal((await readFile(join(app.directory, 'events.jsonl'), 'utf8')).trim().split('\n').length, 3);
  assert.ok(!(JSON.stringify(state)).includes(app.config.secretBase64));
  assert.ok(!(JSON.stringify(state)).includes(app.config.sipPassword));
  assert.match(await (await fetch(app.url)).text(), /福大接口模拟器/);
});
test('inspection and control reject foreign origins and control requires its local header', async t => {
  const app = await fixture(t);
  assert.equal((await fetch(app.url + '/api/demo/data', { method: 'POST' })).status, 403);
  assert.equal((await fetch(app.url + '/api/demo/data', { ...post(), headers: { ...post().headers, Origin: 'https://outside.invalid' } })).status, 403);
  const status = await new Promise((resolve, reject) => {
    http.get(app.url + '/api/state', { headers: { Host: 'outside.invalid' } }, res => { res.resume(); resolve(res.statusCode); }).on('error', reject);
  });
  assert.equal(status, 403);
  assert.equal((await fetch(app.url + '/receive', { method: 'POST', body: '{}' })).status, 401);
});
test('repeated close awaits the same ongoing media cleanup', async t => {
  const app = await fixture(t), original = app.upper.close.bind(app.upper);
  let release; const gate = new Promise(resolve => { release = resolve; });
  app.upper.close = async () => { await gate; return original(); };
  const first = app.close(); let secondFinished = false;
  const second = app.close().then(() => { secondFinished = true; });
  await new Promise(resolve => setTimeout(resolve, 20));
  const prematurelyClosed = secondFinished; release(); await Promise.all([first, second]);
  assert.equal(prematurelyClosed, false);
});
for (const transport of ['UDP', 'TCP']) test(`video simulation performs actual SIP registration, catalog and ${transport} media capture`, { skip: !process.env.FFMPEG_PATH }, async t => {
  const app = await fixture(t);
  assert.equal((await fetch(app.url + '/api/demo/video', post())).status, 200);
  const state = await (await fetch(app.url + '/api/state')).json();
  assert.equal(state.video.registered, true);
  assert.equal(state.video.channels.length, 1);
  const played = await fetch(app.url + '/api/video/play', post({ channelId: state.video.channels[0].channelId, transport }));
  assert.equal(played.status, 200, await played.text());
  await until(async () => (await (await fetch(app.url + '/api/state')).json()).video.active?.packets > 30);
  assert.equal((await fetch(app.url + '/api/video/stop', post())).status, 200);
  const finished = await until(async () => (await (await fetch(app.url + '/api/state')).json()).recordings.find(x => x.mp4File));
  const range = await fetch(app.url + '/recordings/' + finished.mp4File, { headers: { Range: 'bytes=0-99' } });
  assert.equal(range.status, 206);
  assert.equal((await range.arrayBuffer()).byteLength, 100);
});
