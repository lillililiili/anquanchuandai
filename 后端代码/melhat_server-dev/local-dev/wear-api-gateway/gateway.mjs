import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const PREFIX = '/api/guardian/v1';
const ID = '[A-Za-z0-9_-]{1,100}';
const patterns = [
  ['POST', '/(?:mobile/)?login'], ['POST', '/logout'], ['GET', '/operator'],
  ['GET', '/mobile/(?:identity|sites|context|home|people|devices|works|assignments|calls)'],
  ['GET', `/mobile/(?:people|devices|works)/${ID}`],
  ['POST', '/mobile/assignments/(?:issue|return)'],
  ['POST', '/mobile/(?:calls|broadcast)'],
  ['GET', `/mobile/calls/${ID}(?:/credentials)?`],
  ['POST', `/mobile/calls/${ID}/(?:joined|end)`],
  ['GET', `/events(?:/${ID})?`],
  ['POST', `/events/${ID}/(?:claim|observations|verification-draft|verification|photos|assist-join|assist-end)`],
  ['POST', '/sos'], ['GET', `/files/${ID}`], ['PUT', `/files/${ID}`],
  ['GET', `/devices/${ID}/(?:media|live)`], ['POST', `/devices/${ID}/commands`],
  ['GET', `/helmet/calls/${ID}(?:/credentials)?`], ['GET', '/locations/history'], ['GET', `/locations/people/${ID}`],
  ['GET', '/helmet/media'],
  ['POST', '/(?:call|call/end|broadcast)'],
].map(([method, pattern]) => [method, new RegExp(`^${PREFIX}${pattern}$`)]);
export function allowed(method, pathname) { return patterns.some(([m, pattern]) => m === method && pattern.test(pathname)); }
const login = pathname => pathname === `${PREFIX}/login` || pathname === `${PREFIX}/mobile/login`;
function fail(response, status, code) { response.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' }); response.end(JSON.stringify({ code: status, error: code })); }
export function createWearGateway({ upstreamOrigin = 'http://127.0.0.1:18084', testOnly = false } = {}) {
  const upstream = new URL(upstreamOrigin);
  if (upstream.protocol !== 'http:' || upstream.hostname !== '127.0.0.1' || upstream.origin !== upstreamOrigin
    || (!testOnly && upstream.port !== '18084') || (testOnly && upstream.port === '18084')) throw Error('Expected isolated local backend');
  const limits = new Map();
  const take = (key, max) => {
    const now = Date.now();
    if (limits.size > 10000) for (const [k, v] of limits) if (v.until < now) limits.delete(k);
    if (limits.size > 10000) return false;
    let entry = limits.get(key); if (!entry || entry.until < now) { entry = { count: 0, until: now + 60000 }; limits.set(key, entry); }
    return ++entry.count <= max;
  };
  const server = http.createServer({ maxHeaderSize: 8192 }, (request, response) => {
    const raw = request.url ?? '';
    if (!raw.startsWith('/') || raw.startsWith('//') || raw.length > 4096 || /%2f|%5c|%00|\\|\.\.|#/i.test(raw)) return fail(response, 400, 'INVALID_PATH');
    const url = new URL(raw, 'http://localhost');
    if (!allowed(request.method, url.pathname)) return fail(response, 404, 'NOT_FOUND');
    const queryKeys = ['siteId', 'eventId', 'deviceId', 'personId', 'status', 'type', 'pageNum', 'pageSize', 'from', 'to', 'after', 'cursor', 'limit'];
    const liveRoute = request.method === 'GET' && new RegExp(`^${PREFIX}/devices/${ID}/live$`).test(url.pathname);
    if (liveRoute) {
      queryKeys.push('assignmentId', 'assignmentVersion', 'viewerSessionId');
    }
    if ([...url.searchParams.keys()].some(k => !queryKeys.includes(k))
      || [...url.searchParams.keys()].some(k => url.searchParams.getAll(k).length !== 1)) return fail(response, 400, 'INVALID_QUERY');
    if (liveRoute) {
      for (const key of ['personId', 'assignmentId']) if (url.searchParams.has(key)
        && !/^[A-Za-z0-9_-]{1,100}$/.test(url.searchParams.get(key))) return fail(response, 400, 'INVALID_QUERY');
      if (url.searchParams.has('viewerSessionId') && !/^[A-Za-z0-9_-]{8,100}$/.test(url.searchParams.get('viewerSessionId'))) return fail(response, 400, 'INVALID_QUERY');
      const version = url.searchParams.get('assignmentVersion');
      if (version !== null && (!/^[1-9][0-9]*$/.test(version) || !Number.isSafeInteger(Number(version)))) return fail(response, 400, 'INVALID_QUERY');
    }
    const token = request.headers['x-wearable-token'];
    if (!login(url.pathname) && !/^[A-Za-z0-9_-]{43}$/.test(token ?? '')) return fail(response, 401, 'SESSION_REQUIRED');
    // Caddy replaces X-Real-IP; the gateway binds loopback behind its exclusive tunnel.
    const source = /^[0-9a-f:.]{3,64}$/i.test(request.headers['x-real-ip'] ?? '') ? request.headers['x-real-ip'] : 'local';
    if (!take(`${login(url.pathname) ? 'login' : token}:${source}`, login(url.pathname) ? 12 : 180)) return fail(response, 429, 'RATE_LIMIT');
    const maximum = request.method === 'PUT' && /\/files\//.test(url.pathname) ? 10 * 1024 * 1024 : 128 * 1024;
    const declared = Number(request.headers['content-length'] ?? 0);
    if (!Number.isSafeInteger(declared) || declared < 0 || declared > maximum) return fail(response, 413, 'BODY_TOO_LARGE');
    const chunks = []; let length = 0, rejected = false;
    request.on('data', chunk => { length += chunk.length; if (length > maximum) { rejected = true; request.resume(); if (!response.headersSent) fail(response, 413, 'BODY_TOO_LARGE'); } else chunks.push(chunk); });
    request.on('end', () => {
      if (rejected) return;
      const body = Buffer.concat(chunks);
      const headers = { Accept: 'application/json', 'Content-Length': String(body.length) };
      if (token) headers['X-Wearable-Token'] = token;
      if (request.headers['content-type']) headers['Content-Type'] = request.headers['content-type'];
      if (request.headers['x-wearable-revision']) headers['X-Wearable-Revision'] = request.headers['x-wearable-revision'];
      const outgoing = http.request(new URL(url.pathname + url.search, upstream), { method: request.method, headers, timeout: 30000 }, incoming => {
        response.writeHead(incoming.statusCode, { 'Content-Type': incoming.headers['content-type'] ?? 'application/json', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' });
        let received = 0;
        incoming.on('data', chunk => { received += chunk.length; if (received > 20 * 1024 * 1024) { incoming.destroy(); response.destroy(); } else response.write(chunk); });
        incoming.on('end', () => response.end()); incoming.on('error', () => response.destroy());
      });
      outgoing.on('timeout', () => outgoing.destroy());
      outgoing.on('error', () => { if (!response.headersSent) fail(response, 502, 'BACKEND_UNAVAILABLE'); else response.destroy(); });
      response.on('close', () => outgoing.destroy()); outgoing.end(body);
    });
    request.on('error', () => { if (!response.headersSent) fail(response, 400, 'REQUEST_FAILED'); });
  });
  server.requestTimeout = 35000; server.headersTimeout = 5000; server.keepAliveTimeout = 1000;
  server.on('upgrade', (_req, socket) => socket.end('HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n'));
  return server;
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const server = createWearGateway(); server.listen(18088, '127.0.0.1', () => console.log('Wear API gateway listening on loopback 18088'));
  for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => server.close());
}
