import http from 'node:http';
import { timingSafeEqual, randomUUID } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const PREFIX = '/api/helmet/notify/';
const KINDS = new Set(['gnss', 'baro', 'deviceStatus', 'sosCall', 'sosCallEnd', 'sos']);
const SN = /^[A-Za-z0-9._-]{1,64}$/;
function secretEqual(actual, expected) {
  const a = Buffer.from(typeof actual === 'string' ? actual : '');
  const b = Buffer.from(expected);
  return a.length === b.length && timingSafeEqual(a, b);
}
function origin(value, testOnly) {
  const parsed = new URL(value);
  if (parsed.username || parsed.password || parsed.search || parsed.hash
    || !(parsed.protocol === 'https:' || testOnly && parsed.protocol === 'http:' && parsed.hostname === '127.0.0.1')) throw Error('Expected HTTPS callback origin without credentials');
  return value.replace(/\/$/, '');
}
export function validateConfig(input, testOnly = false) {
  if (!input || !Number.isSafeInteger(input.version) || input.version < 1) throw Error('A positive routing version is required');
  // Preserve the existing manufacturer's secret; the independent new receiver uses a new secret.
  for (const field of ['incomingSecret', 'wearableSecret']) if (typeof input[field] !== 'string' || input[field].length < (field === 'wearableSecret' ? 32 : 1) || input[field].length > 2048 || /[\r\n]/.test(input[field])) throw Error('Set the existing incoming secret and an independent wearable secret of at least 32 characters');
  if (!input.routes || typeof input.routes !== 'object' || Array.isArray(input.routes)) throw Error('Explicit routes are required');
  const routes = Object.create(null);
  for (const [sn, target] of Object.entries(input.routes)) {
    if (!SN.test(sn) || !['wearable', 'paused'].includes(target)) throw Error('Invalid explicit SN route');
    routes[sn] = target;
  }
  return Object.freeze({ ...input, routes: Object.freeze(routes),
    legacyOrigin: origin(input.legacyOrigin, testOnly), wearableOrigin: origin(input.wearableOrigin, testOnly) });
}

export class Inbox {
  constructor(filename) {
    this.db = new DatabaseSync(filename);
    this.db.exec(`PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA busy_timeout=5000;
      CREATE TABLE IF NOT EXISTS delivery (
        seq INTEGER PRIMARY KEY AUTOINCREMENT, ingress_id TEXT NOT NULL UNIQUE,
        sn TEXT NOT NULL, kind TEXT NOT NULL, body TEXT NOT NULL, received_at TEXT NOT NULL,
        target TEXT NOT NULL, route_version INTEGER NOT NULL, attempts INTEGER NOT NULL DEFAULT 0,
        next_attempt INTEGER NOT NULL DEFAULT 0, acknowledged INTEGER NOT NULL DEFAULT 0,
        last_status INTEGER, acknowledged_at TEXT);
      CREATE INDEX IF NOT EXISTS delivery_pending ON delivery(acknowledged,next_attempt,seq);`);
  }
  add(entry) {
    this.db.prepare('INSERT INTO delivery(ingress_id,sn,kind,body,received_at,target,route_version) VALUES(?,?,?,?,?,?,?)')
      .run(entry.id, entry.sn, entry.kind, entry.body, entry.receivedAt, entry.target, entry.version);
  }
  next(now, paused = []) {
    return this.db.prepare(`SELECT * FROM delivery d WHERE acknowledged=0 AND next_attempt<=?
      ${paused.length ? `AND sn NOT IN (${paused.map(() => '?').join(',')})` : ''}
      AND NOT EXISTS(SELECT 1 FROM delivery older WHERE older.sn=d.sn AND older.acknowledged=0 AND older.seq<d.seq)
      ORDER BY seq LIMIT 1`).get(now, ...paused);
  }
  acknowledge(id) { this.db.prepare('UPDATE delivery SET acknowledged=1,last_status=200,acknowledged_at=? WHERE ingress_id=?').run(new Date().toISOString(), id); }
  retry(id, attempts, status, now) {
    this.db.prepare('UPDATE delivery SET attempts=?,last_status=?,next_attempt=? WHERE ingress_id=?')
      .run(attempts, status, now + Math.min(300000, 1000 * 2 ** Math.min(attempts, 8)), id);
  }
  summary() {
    return this.db.prepare('SELECT COUNT(*) AS total,SUM(CASE WHEN acknowledged=0 THEN 1 ELSE 0 END) AS pending FROM delivery').get();
  }
  close() { this.db.close(); }
}

function reply(response, status, code) {
  response.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
  response.end(JSON.stringify({ code: status, message: code }));
}
async function bodyOf(request) {
  const chunks = []; let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > 65536) throw Error('BODY_TOO_LARGE');
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

export function createRouter({ config, filename, inbox: suppliedInbox, testOnly = false, timeoutMs = 10000, clock = Date.now }) {
  const cfg = validateConfig(config, testOnly);
  let inbox = suppliedInbox, inboxError = false;
  if (!inbox) {
    try { inbox = new Inbox(filename); } catch { inboxError = true; }
  }
  let pumping = false;
  async function pump() {
    if (pumping || !inbox || inboxError) return;
    pumping = true;
    let item;
    try {
      item = inbox.next(clock(), Object.keys(cfg.routes).filter(sn => cfg.routes[sn] === 'paused'));
      if (!item) return;
      // The destination/version are frozen at receipt; later routing changes cannot reassign evidence.
      const response = await fetch(item.target + PREFIX + item.kind, {
        method: 'POST', redirect: 'manual', signal: AbortSignal.timeout(timeoutMs),
        headers: { 'Content-Type': 'application/json', 'X-Helmet-Callback-Secret': cfg.wearableSecret,
          'X-Split-Ingress-Id': item.ingress_id, 'X-Split-Received-At': item.received_at }, body: item.body,
      });
      const text = await response.text();
      let accepted = false;
      try { accepted = response.ok && JSON.parse(text).code === 200; } catch { /* Not an application acknowledgement. */ }
      if (accepted) inbox.acknowledge(item.ingress_id);
      else inbox.retry(item.ingress_id, item.attempts + 1, response.status, clock());
    } catch {
      if (item) { try { inbox.retry(item.ingress_id, item.attempts + 1, 0, clock()); } catch { inboxError = true; } }
      else inboxError = true;
    } finally { pumping = false; }
  }
  const server = http.createServer({ maxHeaderSize: 8192 }, async (request, response) => {
    const rawPath = request.url || '';
    if (request.method !== 'POST' || !rawPath.startsWith(PREFIX) || !KINDS.has(rawPath.slice(PREFIX.length))) return reply(response, 404, 'NOT_FOUND');
    if (!secretEqual(request.headers['x-helmet-callback-secret'], cfg.incomingSecret)) return reply(response, 401, 'CALLBACK_AUTH_REQUIRED');
    if (!/^application\/json(?:\s*;|$)/i.test(request.headers['content-type'] || '')) return reply(response, 415, 'JSON_REQUIRED');
    const declared = request.headers['content-length'];
    if (declared && (!/^\d+$/.test(declared) || Number(declared) > 65536)) return reply(response, 413, 'BODY_TOO_LARGE');
    let body, payload;
    try { body = await bodyOf(request); payload = JSON.parse(body.toString('utf8')); }
    catch (error) { if (!response.destroyed) reply(response, error.message === 'BODY_TOO_LARGE' ? 413 : 400, 'INVALID_BODY'); return; }
    if (!payload || Array.isArray(payload) || typeof payload.helmetSn !== 'string' || !SN.test(payload.helmetSn)) return reply(response, 400, 'INVALID_SN');
    const target = cfg.routes[payload.helmetSn];
    if (target === 'paused') return reply(response, 409, 'DEVICE_ROUTE_PAUSED');
    if (target === 'wearable') {
      if (!inbox || inboxError) return reply(response, 503, 'INBOX_UNAVAILABLE');
      try {
        inbox.add({ id: randomUUID(), sn: payload.helmetSn, kind: rawPath.slice(PREFIX.length), body: body.toString('utf8'),
          receivedAt: new Date(clock()).toISOString(), target: cfg.wearableOrigin, version: cfg.version });
      } catch { return reply(response, 503, 'INBOX_UNAVAILABLE'); }
      return reply(response, 200, 'success');
    }
    // Existing platform is intentionally NOT queued/retried: its callbacks are not idempotent.
    try {
      const old = await fetch(cfg.legacyOrigin + rawPath, { method: 'POST', redirect: 'manual', signal: AbortSignal.timeout(timeoutMs),
        headers: { 'Content-Type': request.headers['content-type'], 'X-Helmet-Callback-Secret': cfg.incomingSecret }, body });
      const bytes = Buffer.from(await old.arrayBuffer());
      const headers = { 'Content-Type': old.headers.get('content-type') || 'application/json', 'Cache-Control': 'no-store' };
      if (old.headers.has('location')) headers.Location = old.headers.get('location');
      response.writeHead(old.status, headers); response.end(bytes);
    } catch { if (!response.destroyed) reply(response, 502, 'LEGACY_DELIVERY_UNKNOWN_NOT_RETRIED'); }
  });
  server.requestTimeout = 15000; server.headersTimeout = 5000;
  server.on('upgrade', (_request, socket) => socket.end('HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n'));
  return { server, pump, inbox, healthy: () => !inboxError };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const configPath = process.env.SPLIT_ROUTER_CONFIG;
  if (!configPath) throw Error('Set SPLIT_ROUTER_CONFIG to an explicit local configuration');
  const config = JSON.parse(readFileSync(configPath, 'utf8').replace(/^\uFEFF/, ''));
  config.incomingSecret = process.env.SPLIT_ROUTER_INCOMING_SECRET;
  config.wearableSecret = process.env.SPLIT_ROUTER_WEARABLE_SECRET;
  if (!config.databasePath || !path.isAbsolute(config.databasePath)) throw Error('An absolute persistent databasePath is required');
  const app = createRouter({ config, filename: config.databasePath });
  const port = config.listenPort || 18089;
  if (!Number.isSafeInteger(port) || port < 1024 || port > 65535) throw Error('Invalid listen port');
  app.server.listen(port, '127.0.0.1', () => console.log('Split helmet callback router listening on loopback'));
  const timer = setInterval(() => { void app.pump(); }, 500);
  for (const signal of ['SIGTERM', 'SIGINT']) process.on(signal, () => {
    clearInterval(timer); app.server.close(() => process.exit(0));
  });
}
