import { mkdir, readFile, writeFile, readdir, stat } from 'node:fs/promises';
import { createReadStream, existsSync, readdirSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash, createHmac, randomBytes, randomUUID } from 'node:crypto';
import { createReceiver } from '../fuda-push/mock-receiver.mjs';
import { UpperPlatform } from './sip-upper.mjs';
import { createDemoBridge } from './demo-source.mjs';

const here = dirname(fileURLToPath(import.meta.url));
function ffmpegLocation() {
  if (process.env.FFMPEG_PATH) return process.env.FFMPEG_PATH;
  const folder = join(here, '.local/tools/imageio_ffmpeg/binaries');
  if (existsSync(folder)) return readdirSync(folder).filter(x => /^ffmpeg.*(?:\.exe)?$/.test(x)).map(x => join(folder, x))[0];
}
const json = (res, status, data) => { res.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' }); res.end(JSON.stringify(data)); };
async function input(req) {
  let size = 0; const chunks = [];
  for await (const chunk of req) { size += chunk.length; if (size > 4096) throw Error('请求过大'); chunks.push(chunk); }
  return JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}');
}
async function recordings(folder) {
  const rows = [];
  for (const name of await readdir(folder)) {
    if (!/^[A-Za-z0-9_-]{1,80}\.json$/.test(name)) continue;
    try { const row = JSON.parse(await readFile(join(folder, name), 'utf8')); if (row.endedAt) rows.push(row); } catch {}
  }
  return rows.sort((a, b) => b.startedAt.localeCompare(a.startedAt)).slice(0, 30);
}

export async function startSimulator({ directory = join(here, '.local'), httpPort = 19091, sipPort = 15061, ffmpegPath = ffmpegLocation() } = {}) {
  for (const port of [httpPort, sipPort]) if (!Number.isInteger(port) || port < 0 || port > 65535) throw Error('端口应为 0–65535');
  await mkdir(directory, { recursive: true });
  const configFile = join(directory, 'config.json');
  let config;
  try { config = JSON.parse(await readFile(configFile, 'utf8')); }
  catch (e) {
    if (e.code !== 'ENOENT') throw Error('模拟器配置损坏，请检查 .local/config.json');
    config = { appId: 'fuda-local-simulator', secretBase64: randomBytes(32).toString('base64'), upperId: '34020000002000000001',
      realm: '3402000000', sipUsername: '34020000002000000002', sipPassword: randomBytes(18).toString('hex') };
    await writeFile(configFile, JSON.stringify(config, null, 2) + '\n', { flag: 'wx', mode: 0o600 });
  }
  const mediaFolder = join(directory, 'recordings'); await mkdir(mediaFolder, { recursive: true });
  const upper = new UpperPlatform({ id: config.upperId, realm: config.realm, username: config.sipUsername, password: config.sipPassword,
    port: sipPort, directory: mediaFolder, ffmpegPath });
  let receiver, demo, demoStarting, url, closePromise;
  async function other(req, res) {
    try {
      if (req.headers.host !== new URL(url).host || (req.headers.origin && req.headers.origin !== url)) return json(res, 403, { error: '只允许本机页面访问' });
      const route = new URL(req.url, url);
      if (req.method === 'GET' && route.pathname === '/') {
        res.writeHead(200, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store', 'x-content-type-options': 'nosniff',
          'content-security-policy': "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; media-src 'self'; frame-ancestors 'none'" });
        return res.end(await readFile(join(here, 'index.html')));
      }
      if (req.method === 'GET' && route.pathname === '/api/state') {
        const rows = [...receiver.events.values()].reverse(), counts = { POSITION: 0, STATUS: 0, ALARM: 0 };
        for (const row of rows) counts[row.event.eventType]++;
        const type = route.searchParams.get('type');
        return json(res, 200, { data: { total: rows.length, requests: receiver.requests, rejected: receiver.rejected, duplicates: receiver.duplicates,
          counts, events: rows.filter(row => !type || row.event.eventType === type).slice(0, 50) }, video: upper.snapshot(),
          recordings: await recordings(mediaFolder), connection: { receiveUrl: url + '/receive', appId: config.appId,
            upperId: config.upperId, realm: config.realm, sipUsername: config.sipUsername, sipPort: upper.port, host: '127.0.0.1',
            ffmpegAvailable: !!ffmpegPath, syntheticPeer: !!demo }, limits: { eventCount: 5000, eventStorageMiB: 64, videoMinutes: 5, videoMiB: 256 } });
      }
      if (req.method === 'GET' && /^\/recordings\/[A-Za-z0-9_-]{1,80}\.(?:mp4|ps)$/.test(route.pathname)) {
        const name = route.pathname.split('/').at(-1), filename = join(mediaFolder, name);
        let info; try { info = await stat(filename); } catch { return json(res, 404, { error: '文件尚未生成' }); }
        const type = name.endsWith('.mp4') ? 'video/mp4' : 'application/octet-stream';
        let start = 0, end = info.size - 1, status = 200;
        if (req.headers.range) {
          const range = /^bytes=(\d+)-(\d*)$/.exec(req.headers.range);
          if (!range || Number(range[1]) >= info.size || (range[2] && Number(range[2]) < Number(range[1]))) { res.writeHead(416, { 'content-range': `bytes */${info.size}` }); return res.end(); }
          start = Number(range[1]); end = range[2] ? Math.min(Number(range[2]), end) : end; status = 206;
        }
        if (info.size === 0) return json(res, 409, { error: '还未收到视频数据' });
        res.writeHead(status, { 'content-type': type, 'accept-ranges': 'bytes', 'content-length': end - start + 1,
          ...(status === 206 ? { 'content-range': `bytes ${start}-${end}/${info.size}` } : {}) });
        const stream = createReadStream(filename, { start, end }); stream.on('error', () => res.destroy()); res.on('close', () => stream.destroy());
        return stream.pipe(res);
      }
      if (req.method !== 'POST') return json(res, 404, { error: '接口不存在' });
      if (req.headers['x-simulator-request'] !== '1') return json(res, 403, { error: '请从模拟器页面操作' });
      const body = await input(req);
      if (route.pathname === '/api/demo/data') {
        for (const type of ['position', 'status', 'alarm']) {
          const event = JSON.parse(await readFile(join(here, '../fuda-push/examples', type + '.json'), 'utf8'));
          event.eventId = 'FP-' + randomBytes(32).toString('hex'); event.createdAt = new Date().toISOString();
          if (event.eventType === 'ALARM') event.data.eventId = 'example-' + randomUUID();
          const raw = JSON.stringify(event), timestamp = String(Math.floor(Date.now() / 1000)), nonce = randomUUID();
          const signature = createHmac('sha256', Buffer.from(config.secretBase64, 'base64'))
            .update(['POST', '/receive', config.appId, timestamp, nonce, createHash('sha256').update(raw).digest('hex')].join('\n')).digest('hex');
          const result = await fetch(url + '/receive', { method: 'POST', body: raw, headers: { 'content-type': 'application/json', 'x-app-id': config.appId,
            'x-timestamp': timestamp, 'x-nonce': nonce, 'x-signature': signature }, signal: AbortSignal.timeout(5000) });
          if (!result.ok) throw Error('测试报文未被接收，请检查存储容量');
        }
        return json(res, 200, { ok: true });
      }
      if (route.pathname === '/api/demo/video') {
        if (upper.snapshot().registered && !demo && !demoStarting) return json(res, 409, { error: '已有外部下级平台注册，请使用现有通道' });
        if (!demo) {
          demoStarting ??= createDemoBridge({ upper, config, directory, ffmpegPath }).then(value => { demo = value; }).finally(() => { demoStarting = null; });
          await demoStarting;
        }
        return json(res, 200, { ok: true });
      }
      if (route.pathname === '/api/video/catalog') { await upper.catalog(); return json(res, 200, { ok: true }); }
      if (route.pathname === '/api/video/play') { await upper.play(body.channelId, { transport: body.transport }); return json(res, 200, { ok: true }); }
      if (route.pathname === '/api/video/stop') { await upper.stop(); return json(res, 200, { ok: true }); }
      return json(res, 404, { error: '接口不存在' });
    } catch (error) { if (!res.headersSent) json(res, 400, { error: error.message }); else res.destroy(); }
  }
  try {
    receiver = createReceiver({ appId: config.appId, secretBase64: config.secretBase64, storageFile: join(directory, 'events.jsonl'), handleOther: other });
    await upper.start();
    await new Promise((done, fail) => { receiver.server.once('error', fail); receiver.server.listen(httpPort, '127.0.0.1', done); });
    url = `http://127.0.0.1:${receiver.server.address().port}`;
  } catch (e) { await upper.close(); throw e; }
  return { url, directory, config, receiver, upper, close() {
    closePromise ??= (async () => {
      if (demoStarting) await demoStarting.catch(() => {});
      await upper.close(); await demo?.close();
      await new Promise(done => { receiver.server.close(done); receiver.server.closeAllConnections(); });
    })();
    return closePromise;
  } };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const app = await startSimulator({ httpPort: Number(process.env.SIM_HTTP_PORT || 19091), sipPort: Number(process.env.SIM_SIP_PORT || 15061) });
  console.log(`福大本地模拟器: ${app.url}\n数据接收: ${app.url}/receive\nSIP UDP/TCP: 127.0.0.1:${app.upper.port}\n测试凭据保存在 .local/config.json（未使用正式凭据）`);
  for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => app.close().then(() => process.exit(0)));
}
