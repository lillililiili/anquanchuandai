import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { verifier } from './auth.mjs';
import { MediaService, CONTROL, PUBLIC, fault, id } from './service.mjs';
import { subscribeEsl } from './esl.mjs';
import { spool } from './spool.mjs';

export function configuration(env = process.env) {
  const config = { publicOrigin: env.MEDIA_PUBLIC_ORIGIN ?? 'https://lingzhiaide.com', publicIp: env.MEDIA_PUBLIC_IP ?? '39.106.212.138',
    sipHost: env.MEDIA_SIP_HOST ?? '39.106.212.138', signingKey: env.MEDIA_SIGNING_KEY, hookKey: env.MEDIA_HOOK_KEY,
    eslPassword: env.MEDIA_ESL_PASSWORD, turnSecret: env.MEDIA_TURN_SECRET, dataDir: env.MEDIA_DATA_DIR ?? '/data',
    srsApi: env.MEDIA_SRS_API ?? 'http://127.0.0.1:1985', srsHttp: env.MEDIA_SRS_HTTP ?? 'http://127.0.0.1:8080',
    ttsOrigin: env.MEDIA_TTS_ORIGIN ?? 'http://127.0.0.1:18192', host: env.MEDIA_LISTEN_HOST ?? '127.0.0.1', port: Number(env.MEDIA_PORT ?? 18190),
    browserOrigins: (env.MEDIA_BROWSER_ORIGINS ?? 'https://lingzhiaide.com,http://localhost:5191,http://127.0.0.1:5191,http://localhost:5181,http://127.0.0.1:5181').split(',') };
  for (const key of ['signingKey', 'hookKey', 'eslPassword', 'turnSecret']) if (!/^[A-Za-z0-9_-]{32,128}$/.test(config[key] ?? '')) throw Error(`Missing or invalid ${key}`);
  if (new URL(config.publicOrigin).protocol !== 'https:' || !/^[A-Za-z0-9.-]+$/.test(config.sipHost)) throw Error('Invalid public media address');
  return config;
}
export function reply(response, status, value) {
  response.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' });
  response.end(JSON.stringify(value));
}
export async function readBody(request, maximum = 128 * 1024) {
  if (Number(request.headers['content-length'] ?? 0) > maximum) throw fault(413, 'BODY_TOO_LARGE');
  const chunks = []; let size = 0;
  for await (const chunk of request) { size += chunk.length; if (size > maximum) throw fault(413, 'BODY_TOO_LARGE'); chunks.push(chunk); }
  return Buffer.concat(chunks);
}
function json(bytes) { try { return bytes.length ? JSON.parse(bytes) : {}; } catch { throw fault(400, 'INVALID_JSON'); } }
function hlsContext(query, status = 400) {
  if ([...query.keys()].some(key => key !== 'token' && key !== 'hls_ctx')
      || query.getAll('token').length > 1 || query.getAll('hls_ctx').length > 1) throw fault(status, 'INVALID_HLS_QUERY');
  const context = query.get('hls_ctx');
  if (context !== null && !/^[A-Za-z0-9_-]{8,80}$/.test(context)) throw fault(status, 'INVALID_HLS_CONTEXT');
  return context;
}
function hlsSegment(name, streamId) {
  return name.startsWith(streamId + '-') && /^[A-Za-z0-9_-]+\.ts$/.test(name);
}
function hlsPlaylist(bytes, target, streamId, token, context) {
  const text = bytes.toString();
  if (!text.startsWith('#EXTM3U')) throw fault(502, 'INVALID_HLS_PLAYLIST');
  const base = new URL(target);
  const rewrite = value => {
    if (value !== value.trim() || /\.\.|\\|%2e|%2f|%5c/i.test(value)) throw fault(502, 'INVALID_HLS_RESOURCE');
    let uri;
    try { uri = new URL(value, base); } catch { throw fault(502, 'INVALID_HLS_RESOURCE'); }
    if (uri.origin !== base.origin || uri.username || uri.password || uri.hash) throw fault(502, 'INVALID_HLS_RESOURCE');
    const name = uri.pathname.slice('/helmet/'.length);
    if (!uri.pathname.startsWith('/helmet/') || (name !== streamId + '.m3u8' && !hlsSegment(name, streamId)))
      throw fault(502, 'INVALID_HLS_RESOURCE');
    const nextContext = hlsContext(uri.searchParams, 502) ?? context;
    if (uri.searchParams.has('token') && uri.searchParams.get('token') !== token) throw fault(502, 'INVALID_HLS_TICKET');
    const query = new URLSearchParams({ token });
    if (nextContext) query.set('hls_ctx', nextContext);
    return `${name === streamId + '.m3u8' ? 'index.m3u8' : name}?${query}`;
  };
  return text.split(/\r?\n/).map(line => {
    if (!line || !line.startsWith('#')) return line ? rewrite(line) : line;
    if (!line.includes('URI=')) return line;
    let matched = 0;
    const result = line.replace(/\bURI="([^"]+)"/g, (_, uri) => { matched++; return `URI="${rewrite(uri)}"`; });
    if (!matched || matched !== (line.match(/\bURI=/g) ?? []).length) throw fault(502, 'INVALID_HLS_RESOURCE');
    return result;
  }).join('\n');
}
export function createServer(config, dependencies = {}) {
  const service = dependencies.service ?? new MediaService(config, dependencies), verify = verifier(config.signingKey);
  const server = http.createServer({ maxHeaderSize: 8192 }, async (request, response) => {
    try {
      const raw = request.url ?? '';
      if (raw.length > 4096 || /%2f|%5c|%00|\\|\.\./i.test(raw) || raw.includes('#')) throw fault(400, 'INVALID_PATH');
      const url = new URL(raw, 'http://localhost'), pathname = url.pathname;
      const browserOrigin = request.headers.origin;
      if (/^\/helmet-media\/(whep|hls|files)\//.test(pathname) && browserOrigin) {
        if (!(config.browserOrigins ?? [config.publicOrigin]).includes(browserOrigin)) throw fault(403, 'ORIGIN_DENIED');
        response.setHeader('Access-Control-Allow-Origin', browserOrigin);
        response.setHeader('Vary', 'Origin');
        response.setHeader('Access-Control-Expose-Headers', 'Content-Length,Content-Range,Accept-Ranges,Location');
        if (request.method === 'OPTIONS') {
          response.writeHead(204, { 'Access-Control-Allow-Methods': 'GET,HEAD,POST,OPTIONS', 'Access-Control-Allow-Headers': 'Content-Type,Range', 'Access-Control-Max-Age': '600' });
          return response.end();
        }
      }
      if (pathname === '/healthz' && request.method === 'GET') return reply(response, 200, { status: 'running' });
      if (pathname === `/internal/freeswitch/${config.hookKey}` && request.method === 'POST') {
        const body = await readBody(request);
        response.writeHead(200, { 'Content-Type': 'application/xml', 'Cache-Control': 'no-store' });
        return response.end(service.directory(new URLSearchParams(body.toString())));
      }
      if (pathname === `/internal/srs/${config.hookKey}` && request.method === 'POST') return reply(response, 200, service.handleSrs(json(await readBody(request))));
      const file = pathname.match(/^\/helmet-media\/files\/([A-Za-z0-9_-]+)$/);
      if (file && ['GET', 'HEAD'].includes(request.method)) {
        if (!service.authorize(url.searchParams.get('token'), 'asset', file[1])) throw fault(403, 'INVALID_TICKET');
        const asset = service.store.data.assets[file[1]]; if (!asset) throw fault(404, 'ASSET_NOT_FOUND');
        const filename = path.join(service.store.directory, 'assets', asset.filename), stat = fs.statSync(filename);
        const range = request.headers.range;
        let start = 0, end = stat.size - 1, status = 200;
        if (range) {
          const match = /^bytes=(\d+)-(\d*)$/.exec(range); if (!match) throw fault(416, 'INVALID_RANGE');
          start = Number(match[1]); end = match[2] ? Number(match[2]) : end;
          if (start > end || start >= stat.size || end >= stat.size) throw fault(416, 'INVALID_RANGE'); status = 206;
        }
        response.writeHead(status, { 'Content-Type': asset.mime, 'Content-Length': end - start + 1, 'Accept-Ranges': 'bytes',
          'Cache-Control': 'private, no-store', 'X-Content-Type-Options': 'nosniff', ...(status === 206 ? { 'Content-Range': `bytes ${start}-${end}/${stat.size}` } : {}) });
        if (request.method === 'HEAD') return response.end();
        fs.createReadStream(filename, { start, end }).on('error', () => response.destroy()).pipe(response); return;
      }
      const whep = pathname.match(/^\/helmet-media\/whep\/([A-Za-z0-9_-]+)$/);
      if (whep && request.method === 'POST') {
        const stream = service.store.data.streams[whep[1]], token = url.searchParams.get('token');
        if (!stream || stream.status === 'stopped' || !service.authorize(token, 'play', whep[1])) throw fault(403, 'INVALID_TICKET');
        const body = await readBody(request, 65536);
        const target = `${config.srsApi}/rtc/v1/whep/?app=helmet&stream=${whep[1]}&token=${encodeURIComponent(token)}`;
        const upstream = await service.fetch(target, { method: 'POST', body, headers: { 'Content-Type': 'application/sdp' }, signal: AbortSignal.timeout(10000) });
        response.writeHead(upstream.status, { 'Content-Type': upstream.headers.get('content-type') ?? 'application/sdp', 'Cache-Control': 'no-store',
          'Access-Control-Expose-Headers': 'Location' });
        return response.end(await upstream.text());
      }
      const hls = pathname.match(/^\/helmet-media\/hls\/([A-Za-z0-9_-]+)\/([A-Za-z0-9_.-]+)$/);
      if (hls && request.method === 'GET') {
        const [_, streamId, name] = hls, stream = service.store.data.streams[streamId], token = url.searchParams.get('token');
        if (!stream || stream.status === 'stopped' || !service.authorize(token, 'play', streamId)) throw fault(403, 'INVALID_TICKET');
        if (name !== 'index.m3u8' && !hlsSegment(name, streamId)) throw fault(404, 'NOT_FOUND');
        const context = hlsContext(url.searchParams);
        // SRS on_play independently validates the same scoped playback ticket.
        const target = new URL(`${config.srsHttp}/helmet/${name === 'index.m3u8' ? `${streamId}.m3u8` : name}`);
        target.searchParams.set('token', token);
        if (context) target.searchParams.set('hls_ctx', context);
        const upstream = await service.fetch(target.href, { redirect: 'error', signal: AbortSignal.timeout(10000) });
        if (!upstream.ok) throw fault(upstream.status, 'STREAM_UNAVAILABLE');
        const bytes = Buffer.from(await upstream.arrayBuffer());
        const body = name === 'index.m3u8' ? hlsPlaylist(bytes, target, streamId, token, context) : bytes;
        response.writeHead(200, { 'Content-Type': name.endsWith('.m3u8') ? 'application/vnd.apple.mpegurl' : 'video/mp2t', 'Cache-Control': 'no-store' });
        return response.end(body);
      }
      if (!pathname.startsWith(CONTROL + '/')) throw fault(404, 'NOT_FOUND');
      if (!/^\d{10}$/.test(request.headers['x-media-time'] ?? '') || !/^[A-Za-z0-9_-]{16,128}$/.test(request.headers['x-media-nonce'] ?? '')
        || !/^[a-f0-9]{64}$/.test(request.headers['x-media-signature'] ?? '')) throw fault(401, 'INVALID_SIGNATURE');
      const upload = pathname === `${CONTROL}/device-upload`;
      if (upload) {
        if(request.method!=='POST' || !/^[a-f0-9]{64}$/.test(request.headers['x-media-content-sha256']??'') || !verify(request,undefined,request.headers['x-media-content-sha256'])) throw fault(401,'INVALID_SIGNATURE');
        const saved=await spool(request,path.join(service.store.directory,'upload-temp'));
        try {
          if(saved.digest!==request.headers['x-media-content-sha256'])throw fault(400,'BODY_DIGEST_MISMATCH');
          const result=await service.ingestUpload(saved,request.headers['content-type'],url.searchParams.get('deviceId'),url.searchParams.get('kind'),
            { ...(url.searchParams.has('progressId')?{progressId:url.searchParams.get('progressId')}:{}) });
          return reply(response,200,{code:200,data:result});
        }finally{await fs.promises.unlink(saved.filename).catch(()=>{});}
      }
      const body = await readBody(request, upload ? 33 * 1024 * 1024 : 128 * 1024);
      if (!verify(request, body)) throw fault(401, 'INVALID_SIGNATURE');
      const suffix = pathname.slice(CONTROL.length), input = upload ? {} : json(body);
      let result;
      if (request.method === 'GET' && suffix === '/health') result = await service.health();
      else if (request.method === 'PUT' && /^\/accounts\/[A-Za-z0-9_-]+$/.test(suffix)) result = await service.putAccount(suffix.split('/')[2], input);
      else if (request.method === 'POST' && suffix === '/streams') result = service.createStream(input);
      else if (request.method === 'GET' && /^\/streams\/[A-Za-z0-9_-]+$/.test(suffix)) result = await service.streamState(suffix.split('/')[2]);
      else if (request.method === 'DELETE' && /^\/streams\/[A-Za-z0-9_-]+$/.test(suffix)) result = await service.stopStream(suffix.split('/')[2]);
      else if (request.method === 'POST' && suffix === '/calls') result = await service.startCall(input);
      else if (request.method === 'DELETE' && /^\/calls\/[A-Za-z0-9_-]+$/.test(suffix)) result = await service.endCall(suffix.split('/')[2]);
      else if (request.method === 'GET' && /^\/calls\/[A-Za-z0-9_-]+$/.test(suffix)) {
        const call = service.store.data.calls[suffix.split('/')[2]]; if (!call) throw fault(404, 'CALL_NOT_FOUND'); result = await service.callState(call.callId);
      } else if (request.method === 'POST' && suffix === '/tts') result = await service.tts(input);
      else if (request.method === 'POST' && suffix === '/photo-bind') result = service.bindPhoto(input);
      else if (request.method === 'POST' && suffix === '/device-stream-status') {
        const deviceId=id(input.deviceId),stream=Object.values(service.store.data.streams).filter(s=>s.deviceId===deviceId&&s.status!=='stopped').sort((a,b)=>b.createdAt.localeCompare(a.createdAt))[0];
        result=stream?await service.streamState(stream.streamId):{publishing:false,statusVerified:true};
      }
      else if (request.method === 'POST' && suffix === '/recordings') result = await service.startRecording(input);
      else if (request.method === 'GET' && /^\/recordings\/[A-Za-z0-9_-]+$/.test(suffix)) result = service.recordingState(suffix.split('/')[2]);
      else if (request.method === 'DELETE' && /^\/recordings\/[A-Za-z0-9_-]+$/.test(suffix)) result = service.stopRecording(suffix.split('/')[2]);
      else if (request.method === 'GET' && suffix === '/events') {
        const after = Number(url.searchParams.get('after') ?? 0), limit = Math.min(100, Math.max(1, Number(url.searchParams.get('limit') ?? 100)));
        if (!Number.isSafeInteger(after) || !Number.isSafeInteger(limit)) throw fault(400, 'INVALID_CURSOR');
        result = { events: service.store.data.events.filter(e => e.sequence > after).slice(0, limit), latest: service.store.data.sequence,
          oldest: service.store.data.events[0]?.sequence ?? 0 };
      } else if (request.method === 'GET' && (suffix === '/assets' || /^\/devices\/[A-Za-z0-9_-]+\/assets$/.test(suffix))) {
        const deviceId = id(suffix === '/assets' ? url.searchParams.get('deviceId') : suffix.split('/')[2]);
        result = { assets: Object.values(service.store.data.assets).filter(a => a.deviceId === deviceId).map(a => service.assetPublic(a)) };
      } else if (request.method === 'POST' && upload) result = await service.ingestUpload(body, request.headers['content-type'], url.searchParams.get('deviceId'), url.searchParams.get('kind'));
      else throw fault(404, 'NOT_FOUND');
      return reply(response, 200, { code: 200, data: result });
    } catch (error) { if (!response.headersSent) reply(response, error.status ?? 500, { code: error.status ?? 500, error: error.code ?? 'MEDIA_UNAVAILABLE' }); else response.destroy(); }
  });
  server.requestTimeout = 300000; server.headersTimeout = 10000;
  server.on('clientError', (_error, socket) => socket.end('HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n'));
  return { server, service };
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const config = configuration(), { server, service } = createServer(config);
  const unsubscribe = subscribeEsl(config, e => service.handleEsl(e));
  const reap = setInterval(() => service.reapExpired().catch(() => {}), 5000); reap.unref();
  server.listen(config.port, config.host, () => console.log('Helmet media control listening on configured private endpoint'));
  const close = () => { unsubscribe(); clearInterval(reap); service.close(); server.close(); };
  process.on('SIGINT', close); process.on('SIGTERM', close);
}
