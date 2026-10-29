import http from 'node:http';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';

export const ROUTES = new Set(['positions', 'statuses', 'alarms'].map(k => `/openapi/wearables/v2/${k}/query`));
const forwarded = ['content-type', 'x-app-id', 'x-timestamp', 'x-nonce', 'x-signature'];
function fail(res, status, message) {
  if (res.headersSent) return res.destroy();
  res.writeHead(status, {'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store'});
  res.end(JSON.stringify({code: ({400:40001,401:40101,404:40401,413:41301,415:41501,502:50201})[status] ?? status*100+1, message, requestId: randomUUID(), serverTime: new Date().toISOString(), data: null}));
}

/** Exact-path proxy only. The backend authenticates the original signed bytes. */
export function createGateway({upstreamOrigin = 'http://127.0.0.1:18084', testOnly = false} = {}) {
  const upstream = new URL(upstreamOrigin);
  const hosts = testOnly ? ['127.0.0.1'] : ['127.0.0.1', 'backend', '10.255.1.1'];
  if (upstream.protocol !== 'http:' || !hosts.includes(upstream.hostname) || upstream.origin !== upstreamOrigin || upstream.username || upstream.password)
    throw Error('Backend must be the configured private HTTP origin');
  if (testOnly && upstream.port === '18084') throw Error('Tests must not use the daily backend');
  const server = http.createServer({maxHeaderSize: 8192}, (req, res) => {
    if (req.method !== 'POST' || !ROUTES.has(req.url)) return fail(res, 404, 'NOT_FOUND');
    if (req.headers['content-encoding'] || !/^application\/json(?:\s*;\s*charset=(?:utf-8|"utf-8"))?$/i.test(req.headers['content-type'] ?? ''))
      return fail(res, 415, 'JSON_UTF8_REQUIRED');
    const supplied = req.headers['content-length'];
    if (supplied !== undefined && (!/^\d+$/.test(supplied) || Number(supplied) > 65536)) return fail(res, 413, 'BODY_TOO_LARGE');
    for (const name of forwarded.slice(1)) {
      if (typeof req.headers[name] !== 'string' || !req.headers[name]) return fail(res, 401, 'SIGNATURE_HEADERS_REQUIRED');
      if (req.rawHeaders.filter((_, index) => index % 2 === 0).filter(h => h.toLowerCase() === name).length !== 1)
        return fail(res, 400, 'DUPLICATE_HEADER');
    }
    const chunks = []; let bytes = 0, rejected = false;
    req.on('data', chunk => {
      bytes += chunk.length;
      if (bytes > 65536) { rejected = true; chunks.length = 0; if (!res.headersSent) fail(res, 413, 'BODY_TOO_LARGE'); }
      else if (!rejected) chunks.push(chunk);
    });
    req.on('end', () => {
      if (rejected) return;
      const body = Buffer.concat(chunks);
      const headers = Object.fromEntries(forwarded.map(k => [k, req.headers[k]]));
      headers['content-length'] = String(body.length);
      const outgoing = http.request(new URL(req.url, upstream), {method: 'POST', headers, timeout: 10000}, incoming => {
        res.writeHead(incoming.statusCode, {
          'Content-Type': incoming.headers['content-type'] ?? 'application/json; charset=utf-8',
          'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff',
          ...(incoming.headers['retry-after'] ? {'Retry-After': incoming.headers['retry-after']} : {}),
        });
        let received = 0;
        incoming.on('data', chunk => {
          received += chunk.length;
          if (received > 8 * 1024 * 1024) { incoming.destroy(); res.destroy(); } else res.write(chunk);
        });
        incoming.on('end', () => res.end());
        incoming.on('error', () => res.destroy());
      });
      outgoing.on('timeout', () => outgoing.destroy());
      outgoing.on('error', () => fail(res, 502, 'BACKEND_UNAVAILABLE'));
      res.on('close', () => outgoing.destroy());
      outgoing.end(body);
    });
    req.on('error', () => fail(res, 400, 'REQUEST_FAILED'));
  });
  server.headersTimeout = 5000; server.requestTimeout = 15000; server.keepAliveTimeout = 1000;
  server.on('upgrade', (_req, socket) => socket.end('HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n'));
  return server;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const host = process.env.FUDA_GATEWAY_HOST ?? '127.0.0.1';
  if (!['127.0.0.1', '0.0.0.0'].includes(host)) throw Error('Invalid gateway binding');
  const port = Number(process.env.FUDA_GATEWAY_PORT ?? 18089);
  if (!Number.isInteger(port) || port < 1024 || port > 65535) throw Error('Invalid gateway port');
  const server = createGateway({upstreamOrigin: process.env.FUDA_UPSTREAM_ORIGIN ?? 'http://127.0.0.1:18084'});
  server.listen(port, host, () => console.log(`Fuda query gateway listening on ${host}:${port}`));
  for (const signal of ['SIGTERM', 'SIGINT']) process.on(signal, () => server.close());
}
