// Real-media acceptance driver. Run after project-integration and the existing GB bridge.
import fs from 'node:fs';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { headers } from '../fuda-gb-bridge/media.mjs';
import { ffmpegLocation } from './video-source.mjs';

const here = path.dirname(fileURLToPath(import.meta.url)), directory = path.join(here, '.local/integration');
const j = JSON.parse(fs.readFileSync(path.join(directory, 'java-config.json'), 'utf8'));
const evidence = { syntheticInput: true, realComponents: ['Java HelmetMediaService', 'Node MediaService', 'GbBridge', 'SRS', 'ZLMediaKit', 'FFmpeg'], startedAt: new Date().toISOString(), checks: [] };
let ownedSessionId = null;
const sleep = ms => new Promise(r => setTimeout(r, ms));
async function api(route, body) {
  const reply = await fetch(`http://127.0.0.1:19091${route}`, { ...(body === undefined ? {} : { method: 'POST', headers: { 'content-type': 'application/json', 'x-simulator-request': '1', origin: 'http://127.0.0.1:19091' }, body: JSON.stringify(body) }), signal: AbortSignal.timeout(45000) });
  const value = await reply.json(); if (!reply.ok) throw Error(`${route}: ${value.error ?? reply.status}`); return value;
}
async function java(method, route, value) {
  const target = `/internal/fuda-gb/v1${route}`, body = value === undefined ? '' : JSON.stringify(value);
  const reply = await fetch(j.javaOrigin + target, { method, headers: headers(j.javaSecret, method, target, body), ...(body ? { body } : {}), signal: AbortSignal.timeout(20000) });
  const json = await reply.json(); if (!reply.ok || json.code !== 200) throw Error(`Java ${route}: ${json.error ?? json.code}`); return json.data;
}
async function until(check, timeout = 35000) {
  const end = Date.now() + timeout; let value;
  do { value = await check(); if (value) return value; await sleep(300); } while (Date.now() < end);
  throw Error('Integration condition timed out');
}
function decode(record, filename = path.join(here, '.local/recordings', record.mp4File)) {
  const r = spawnSync(ffmpegLocation(), ['-hide_banner', '-nostdin', '-v', 'error', '-i', filename, '-map', '0:v:0', '-map', '0:a:0', '-f', 'null', '-'], { windowsHide: true, encoding: 'utf8', timeout: 30000 });
  if (r.status !== 0 || r.stderr?.trim()) throw Error('Recorded video/audio failed full FFmpeg decode');
  const info = spawnSync(ffmpegLocation(), ['-hide_banner', '-i', filename], { windowsHide: true, encoding: 'utf8', timeout: 10000 }).stderr;
  if (!/Video: h264/.test(info) || !/Audio: aac/.test(info)) throw Error('Expected H264 and AAC tracks');
  return { decodeExitCode: r.status, video: 'H264', audio: 'AAC', mp4File: record.mp4File, psFile: record.psFile,
    packets: record.packets, bytes: record.bytes, lostPackets: record.lostPackets, invalidPackets: record.invalidPackets };
}
async function play(transport) {
  await api('/api/video/catalog', {});
  const s = await api('/api/state'), channel = s.video.channels.find(x => x.channelId === '34020000001320000001' && x.status === 'ON');
  if (!channel) throw Error('Project channel unavailable');
  await api('/api/video/play', { channelId: channel.channelId, transport });
  ownedSessionId = (await api('/api/state')).video.active?.id ?? null;
  const active = await until(async () => { const state = (await api('/api/state')).video.active; return state?.packets > 50 && state; });
  await sleep(6000); return active.id;
}
async function stop(id) {
  await api('/api/video/stop', {});
  ownedSessionId = null;
  const record = await until(async () => (await api('/api/state')).recordings.find(x => x.id === id && x.state === 'ready'));
  await until(async () => Object.keys(JSON.parse(fs.readFileSync(path.join(directory, 'gb-journal.json'), 'utf8'))).length === 0);
  return decode(record);
}
try {
  if (process.argv[2] === 'transport') {
    for (const transport of ['UDP', 'TCP']) {
      const id = await play(transport), decoded = await stop(id);
      evidence.checks.push({ name: `${transport} PS/RTP real receive and decode`, passed: true, ...decoded });
      console.log(`${transport}: ${decoded.packets} RTP packets, H264/AAC full decode passed, GB journal empty`);
    }
  } else if (process.argv[2] === 'other-watcher') {
    const leaseId = `fuda_it_other_watcher_${Date.now()}`;
    let watcher;
    try {
      await java('PUT', `/leases/${leaseId}`, { deviceId: j.deviceId });
      await until(async () => (await java('GET', `/leases/${leaseId}`)).publishing);
      const id = await play('TCP'), source = await java('GET', `/leases/${leaseId}`), watcherFile = `other-watcher-${Date.now()}.mp4`;
      let frames = 0;
      watcher = spawn(ffmpegLocation(), ['-hide_banner', '-nostdin', '-v', 'error', '-i', `rtmp://127.0.0.1:1935/helmet/${source.streamId}?token=${encodeURIComponent(source.playToken)}`,
        '-t', '10', '-map', '0:v:0', '-map', '0:a:0', '-c', 'copy', '-movflags', '+faststart', '-progress', 'pipe:1', '-n', path.join(directory, watcherFile)],
      { windowsHide: true, stdio: ['ignore', 'pipe', 'ignore'] });
      watcher.stdout.on('data', data => { for (const match of data.toString().matchAll(/frame=(\d+)/g)) frames = Number(match[1]); });
      const finished = new Promise((resolve, reject) => { watcher.once('error', () => reject(Error('Independent watcher unavailable'))); watcher.once('close', code => code === 0 ? resolve() : reject(Error('Independent watcher failed'))); });
      finished.catch(() => {});
      await until(() => frames > 10); const framesBeforeStop = frames;
      const decoded = await stop(id), stillWatching = await java('GET', `/leases/${leaseId}`);
      if (!stillWatching.publishing || !stillWatching.statusVerified) throw Error('Independent viewer lost its source');
      await finished;
      if (frames <= framesBeforeStop + 15) throw Error('Independent watcher did not continue after GB stop');
      const otherDecode = decode({ mp4File: watcherFile }, path.join(directory, watcherFile));
      evidence.checks.push({ name: 'Stopping GB playback preserves independent service viewer', passed: true, ...decoded, otherWatcherPublishing: true,
        otherWatcher: { ...otherDecode, framesBeforeStop, framesAfterStop: frames } });
    } finally { watcher?.kill('SIGTERM'); await java('DELETE', `/leases/${leaseId}`); }
    console.log('Independent watcher retained real publishing after GB stop; final lease released.');
  } else if (process.argv[2] === 'source-recovery') {
    const id = await play('UDP'), fixturePid = Number(fs.readFileSync(path.join(directory, 'fixture.pid'), 'utf8').trim());
    if (!Number.isInteger(fixturePid) || fixturePid < 1) throw Error('Fixture PID unavailable');
    const quote = value => `'${value.replaceAll("'", "''")}'`;
    const command = `$children = @(Get-CimInstance Win32_Process -Filter 'ParentProcessId=${fixturePid}' | Where-Object { $_.ExecutablePath -eq ${quote(ffmpegLocation())} -and $_.CommandLine -like '*rtmp://127.0.0.1:1935/helmet/*' }); if ($children.Count -ne 1) { throw 'Exact synthetic publisher not found' }; Stop-Process -Id $children[0].ProcessId`;
    const killed = spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', command], { windowsHide: true, stdio: 'pipe', timeout: 10000 });
    if (killed.status !== 0) throw Error('Synthetic publisher identity check or stop failed');
    const interruptedAt = Date.now();
    const finished = await until(async () => {
      const s = await api('/api/state'); return !s.video.active && s.recordings.find(x => x.id === id && x.state === 'ready');
    }, 45000);
    ownedSessionId = null;
    await until(() => Object.keys(JSON.parse(fs.readFileSync(path.join(directory, 'gb-journal.json'), 'utf8'))).length === 0);
    evidence.checks.push({ name: 'Actual synthetic FFmpeg disconnection triggers lease-renewal loss and releases GB', passed: true, observedReleaseMs: Date.now() - interruptedAt, ...decode(finished) });
    const restarted = await play('TCP'), recovered = await stop(restarted);
    evidence.checks.push({ name: 'Fresh project INVITE after source loss issues a new device publish command and restores real media', passed: true, ...recovered });
    console.log('Real source loss released the session; new INVITE restarted H264/AAC publishing and decoding.');
  } else throw Error('Usage: node video-integration-check.mjs transport|other-watcher|source-recovery');
  evidence.passed = true;
} catch (error) {
  evidence.passed = false; evidence.error = error.message; console.error(error.message); process.exitCode = 1;
  if (ownedSessionId) try { if ((await api('/api/state')).video.active?.id === ownedSessionId) await api('/api/video/stop', {}); } catch {}
}
finally { evidence.finishedAt = new Date().toISOString(); fs.writeFileSync(path.join(directory, `video-${process.argv[2] ?? 'unknown'}-evidence.json`), JSON.stringify(evidence, null, 2)); }
