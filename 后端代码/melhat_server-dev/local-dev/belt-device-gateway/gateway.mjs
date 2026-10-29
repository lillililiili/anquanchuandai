import http from 'node:http';
import { WebSocket, WebSocketServer } from 'ws';
import { validateConfig } from './config.mjs';
import { EVENT_REASONS } from './diagnostics.mjs';

const DEFAULT_LIMITS = Object.freeze({
  maxPayload: 65536, maxBuffered: 262144, maxQueued: 65536,
  maxConnections: 4, messagesPerSecond: 20, upgradesPerMinute: 12,
  requestsPerMinute: 60, authTimeoutMs: 5000, upstreamTimeoutMs: 5000,
  idleTimeoutMs: 90000, closeTimeoutMs: 1000,
});
// Observed after login in the supplied belt log. The vendor leaves these
// accessory requests unanswered; they must not disconnect a valid session.
const IGNORED_ACTIONS = new Set(['getSettingWithDev', 'show_current_battery']);
const ACTIONS = new Set(['ca_login', 'ca_report_location', 'ca_sos', 'ca_sip_sos', ...IGNORED_ACTIONS]);
const RESPONSE_EVENTS = Object.freeze({ ca_login: 'ws_login_response', ca_report_location: 'ws_location_response',
  ca_sos: 'ws_sos_response', ca_sip_sos: 'ws_sip_sos_response', error: 'ws_error_response' });
const QUERY_KEYS = new Set(['ctl', 'act', 'device_id', 'imei', 'app_version', 'ic', 'ca_ver', 'sipphone']);
const MAX_PARAMETERS = 2048;
// The vendor HTTP directory and our WebSocket endpoint have separate roles.
// This is advertised to firmware only; it is never an HTTP proxy destination.
const MANUFACTURER_API_URL = 'http://caps.runde.pro/api/';
// Fixed origin for the requested plain-WebSocket deployment; not a proxy destination.
const DEVICE_WS_ORIGIN = 'ws://39.106.212.138:80';

function parameters(raw) {
  if (raw === '') return new URLSearchParams();
  const parts = raw.split('&');
  if (raw.length > MAX_PARAMETERS || raw.includes('#') || /%(?![0-9a-fA-F]{2})/.test(raw)
      || parts.length > QUERY_KEYS.size || parts.some(part => {
        const equals = part.indexOf('=');
        return equals < 1 || !QUERY_KEYS.has(part.slice(0, equals));
      })) throw new Error('Invalid parameters');
  const values = new URLSearchParams(raw);
  if ([...values.values()].some(value => value.length > 256 || /[\u0000-\u001f\u007f-\u009f\ufffd]/.test(value))) {
    throw new Error('Invalid parameter value');
  }
  return values;
}

async function configurationParameters(request, rawQuery) {
  const rawLength = request.headers['content-length'] ?? '0';
  if (request.headers['transfer-encoding'] || !/^\d+$/.test(rawLength)) throw new Error('Invalid body');
  const length = Number(rawLength);
  if (!Number.isSafeInteger(length) || length > MAX_PARAMETERS || (request.method === 'GET' && length !== 0)) {
    throw new Error('Invalid body size');
  }
  const query = parameters(rawQuery);
  if (length > 0) {
    const contentType = request.headers['content-type'] ?? '';
    if (!/^application\/x-www-form-urlencoded(?:\s*;\s*charset=utf-8)?$/i.test(contentType)) throw new Error('Unsupported body');
    const chunks = [];
    let bytes = 0;
    for await (const chunk of request) {
      bytes += chunk.length;
      if (bytes > MAX_PARAMETERS || bytes > length) throw new Error('Body limit');
      chunks.push(chunk);
    }
    if (bytes !== length || bytes + rawQuery.length > MAX_PARAMETERS) throw new Error('Invalid body size');
    for (const [key, value] of parameters(Buffer.concat(chunks).toString('utf8'))) query.append(key, value);
  }
  if ([...query.keys()].some(key => query.getAll(key).length !== 1)) throw new Error('Duplicate parameters');
  // Observed in the RD1102 belt's boot POST; metadata never reaches upstream.
  if (query.has('sipphone') && !/^[01]$/.test(query.get('sipphone'))) throw new Error('Invalid sipphone flag');
  return query;
}

function counter(max, period) {
  let count = 0, started = Date.now();
  return () => {
    if (Date.now() - started >= period) { started = Date.now(); count = 0; }
    return ++count <= max;
  };
}

function jsonReply(response, status, body) {
  const encoded = JSON.stringify(body);
  response.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(encoded),
    'Cache-Control': 'no-store', 'Connection': 'close', 'X-Content-Type-Options': 'nosniff' });
  response.end(encoded);
}
function failure(response, status, code = 'Unavailable') {
  jsonReply(response, status, { status: false, msg_code: code, msg: 'Device request unavailable' });
}
function rejectUpgrade(socket, status = 404) {
  socket.end(`HTTP/1.1 ${status} Rejected\r\nConnection: close\r\nContent-Length: 0\r\n\r\n`);
}

export function createBeltDeviceGateway(input, { testOnly = false, limits: testLimits = {}, observer } = {}) {
  const config = validateConfig(input, { testOnly });
  if (!testOnly && Object.keys(testLimits).length) throw new Error('Runtime limits are fixed.');
  const limits = { ...DEFAULT_LIMITS, ...testLimits };
  const observationCounts = new Map();
  function observe(event, reason) {
    if (typeof observer !== 'function' || !EVENT_REASONS[event]?.includes(reason)) return;
    const key = `${event}:${reason}`;
    const count = Math.min((observationCounts.get(key) ?? 0) + 1, Number.MAX_SAFE_INTEGER);
    observationCounts.set(key, count);
    // No request, device identity, address, payload or exception is exposed.
    try {
      const result = observer(Object.freeze({ time: new Date().toISOString(), event, reason, count }));
      if (result && typeof result.catch === 'function') result.catch(() => {});
    } catch { /* Diagnostics must never change acceptance or connection handling. */ }
  }
  const bootstrapPaths = new Set([`/${config.pathToken}/api/belt/index.php`,
    `/${config.pathToken}/api/belt/config/index.php`]);
  const websocketPath = `/${config.pathToken}/wsBelt`;
  const deviceWebsocketPath = `/${config.pathToken}/wsHat`;
  // RD1102 truncates its HTTP upgrade request at 199 bytes with the full
  // credential. Keep both existing routes and advertise a 24-character
  // (144-bit) prefix so the observed complete handshake fits in that buffer.
  const shortDeviceWebsocketPath = `/${config.pathToken.slice(0, 24)}/wsHat`;
  const websocketPaths = new Set([websocketPath, deviceWebsocketPath, shortDeviceWebsocketPath]);
  const allowRequest = counter(limits.requestsPerMinute, 60000);
  const allowUpgrade = counter(limits.upgradesPerMinute, 60000);
  const bridges = new Set();
  const pendingHttp = new Set();
  let closing = false;
  const wsServer = new WebSocketServer({ noServer: true, maxPayload: limits.maxPayload,
    perMessageDeflate: false, clientTracking: true });

  async function bootstrap(request, response) {
    const deny = (reason, status, code) => { observe('http_result', reason); return failure(response, status, code); };
    const raw = request.url ?? '';
    const separator = raw.indexOf('?');
    const path = separator === -1 ? raw : raw.slice(0, separator);
    if (!bootstrapPaths.has(path)) return deny('path', 404);
    if (!allowRequest()) return deny('rate', 429);
    if (!['GET', 'POST'].includes(request.method)) return deny('method', 405);
    const rawQuery = separator === -1 ? '' : raw.slice(separator + 1);
    let query;
    try { query = await configurationParameters(request, rawQuery); }
    catch { return deny('parameters', 400); }
    if (query.get('ctl') !== 'config' || query.get('act') !== 'get_config') {
      return deny('action', request.method === 'POST' ? 501 : 400, 'Unsupported');
    }
    // Firmware may use imei on configuration requests or telemetry. Every
    // present identity must agree; only a canonical device_id reaches Spring.
    if (!query.has('device_id') && !query.has('imei')) return deny('identity_missing', 400);
    if (['device_id', 'imei'].some(key => query.has(key) && query.get(key) !== config.deviceId)) return deny('identity_mismatch', 400);
    const abort = new AbortController();
    pendingHttp.add(abort);
    const timer = setTimeout(() => abort.abort(), limits.upstreamTimeoutMs);
    const onClosed = () => abort.abort();
    response.once('close', onClosed);
    try {
      const url = new URL('/api/belt/index.php', config.upstreamOrigin);
      url.search = new URLSearchParams({ ctl: 'config', act: 'get_config', device_id: config.deviceId }).toString();
      observe('http_upstream', 'connecting');
      const upstream = await fetch(url, { redirect: 'error', signal: abort.signal,
        headers: { Accept: 'application/json' } });
      observe('http_upstream', 'connected');
      if (!upstream.ok || Number(upstream.headers.get('content-length') ?? 0) > limits.maxPayload) throw new Error('Upstream unavailable');
      const chunks = [];
      let bytes = 0;
      for await (const chunk of upstream.body) {
        bytes += chunk.length;
        if (bytes > limits.maxPayload) { abort.abort(); throw new Error('Response limit'); }
        chunks.push(chunk);
      }
      const payload = JSON.parse(Buffer.concat(chunks).toString('utf8'));
      if (payload?.status !== true || !payload.data || typeof payload.data.config !== 'string') throw new Error('Invalid configuration');
      const supplied = JSON.parse(payload.data.config);
      if (!supplied || typeof supplied !== 'object' || Array.isArray(supplied)) throw new Error('Invalid configuration');
      const rewritten = { ...payload, data: { ...payload.data, config: JSON.stringify({ ...supplied,
        api_url: MANUFACTURER_API_URL,
        ws_url: `${DEVICE_WS_ORIGIN}${shortDeviceWebsocketPath}` }) } };
      // This gateway has no authority to reset paired accessory configuration.
      delete rewritten.data.extra;
      if (!response.destroyed) { jsonReply(response, 200, rewritten); observe('http_result', 'ok'); }
    } catch {
      observe('http_upstream', 'failed');
      observe('http_result', 'upstream_failure');
      if (!response.destroyed && !response.headersSent) failure(response, 502);
    } finally {
      clearTimeout(timer);
      response.off('close', onClosed);
      pendingHttp.delete(abort);
      abort.abort();
    }
  }

  const server = http.createServer({ maxHeaderSize: 8192 }, (request, response) => {
    observe('http_request', 'received');
    if (closing) { observe('http_result', 'closing'); return failure(response, 503); }
    void bootstrap(request, response).catch(() => {
      observe('http_result', 'internal_failure');
      if (!response.destroyed && !response.headersSent) failure(response, 502);
    });
  });
  server.maxHeadersCount = 24;
  server.requestTimeout = 5000;
  server.headersTimeout = 5000;
  server.keepAliveTimeout = 1000;
  server.on('connection', () => observe('transport_connection', 'open'));
  server.on('clientError', (_error, socket) => {
    observe('http_result', 'malformed_http');
    if (socket.writable) rejectUpgrade(socket, 400);
  });

  function bridge(client) {
    let upstream, ended = false, authenticated = false, queuedBytes = 0;
    let queued = [];
    const allowMessage = counter(limits.messagesPerSecond, 1000);
    let idleTimer;
    const authTimer = setTimeout(() => { observe('ws_first_frame', 'timeout'); cleanup(1008); }, limits.authTimeoutMs);
    const handle = { close: () => { observe('ws_session', 'closing'); cleanup(1001); } };
    bridges.add(handle);

    function touch() {
      clearTimeout(idleTimer);
      idleTimer = setTimeout(() => { observe('ws_session', 'idle'); cleanup(1001); }, limits.idleTimeoutMs);
    }
    function cleanup(code = 1001) {
      if (ended) return;
      ended = true;
      clearTimeout(authTimer);
      clearTimeout(idleTimer);
      queued = []; queuedBytes = 0;
      bridges.delete(handle);
      for (const socket of [client, upstream]) {
        if (!socket) continue;
        if (socket.readyState === WebSocket.CONNECTING) socket.terminate();
        else if (socket.readyState === WebSocket.OPEN) socket.close(code, 'Connection closed');
        const timer = setTimeout(() => {
          if (socket.readyState !== WebSocket.CLOSED) socket.terminate();
        }, limits.closeTimeoutMs);
        timer.unref();
      }
    }
    function send(socket, data, binary = false, act) {
      const size = Buffer.byteLength(data);
      if (socket?.readyState !== WebSocket.OPEN || size > limits.maxPayload
          || socket.bufferedAmount + size > limits.maxBuffered) {
        observe('ws_session', 'backpressure'); cleanup(1009); return false;
      }
      socket.send(data, { binary }, error => {
        if (error) { observe('ws_session', 'send_failed'); cleanup(1011); }
        else if (act) {
          if (act === 'ca_login') observe('ws_login_forwarded', 'ok');
          observe('ws_action_forwarded', act);
        }
      });
      return true;
    }
    function observeResponse(data) {
      // Inspect only cmd/status; never alter, suppress or replace the reply.
      let reply;
      try { reply = JSON.parse(data.toString('utf8')); }
      catch { observe('ws_response_invalid', 'json_invalid'); return; }
      if (!reply || typeof reply !== 'object' || Array.isArray(reply)) {
        observe('ws_response_invalid', 'shape_invalid'); return;
      }
      if (typeof reply.cmd !== 'string' || !Object.hasOwn(RESPONSE_EVENTS, reply.cmd)) {
        observe('ws_response_invalid', 'cmd_unknown'); return;
      }
      observe(RESPONSE_EVENTS[reply.cmd], reply.status === true ? 'true' : reply.status === false ? 'false' : 'invalid');
    }
    function connect() {
      observe('ws_upstream', 'connecting');
      upstream = new WebSocket(`${config.upstreamOrigin.replace(/^http:/, 'ws:')}/wsBelt`, {
        handshakeTimeout: limits.upstreamTimeoutMs, maxPayload: limits.maxPayload,
        perMessageDeflate: false, followRedirects: false,
      });
      upstream.on('error', () => { if (!ended) observe('ws_upstream', 'failed'); cleanup(1011); });
      upstream.on('close', () => { if (!ended) observe('ws_upstream', 'closed'); cleanup(); });
      upstream.on('open', () => {
        if (ended) { upstream.terminate(); return; }
        observe('ws_upstream', 'connected');
        const messages = queued; queued = []; queuedBytes = 0;
        for (const message of messages) if (!send(upstream, message.text, false, message.act)) break;
      });
      upstream.on('message', (data, binary) => {
        if (ended) return;
        if (binary) { observe('ws_session', 'upstream_binary'); cleanup(1003); return; }
        observeResponse(data);
        touch();
        send(client, data);
      });
    }
    client.on('error', () => { if (!ended) observe('ws_session', 'client_error'); cleanup(1011); });
    client.on('close', () => { if (!ended) observe('ws_session', 'client_closed'); cleanup(); });
    function rejectFrame(reason) {
      observe(authenticated ? 'ws_frame_rejected' : 'ws_first_frame', reason);
      cleanup(1008);
    }
    client.on('message', (data, binary) => {
      if (ended) return;
      if (!authenticated) observe('ws_first_frame', 'received');
      if (binary) { rejectFrame('binary'); return; }
      if (!allowMessage()) { rejectFrame('rate'); return; }
      let message;
      try { message = JSON.parse(data.toString('utf8')); } catch { rejectFrame('json_invalid'); return; }
      if (!message || typeof message !== 'object' || Array.isArray(message)) { rejectFrame('shape_invalid'); return; }
      observe('ws_action_received', ACTIONS.has(message.act) ? message.act : 'unknown');
      if (!ACTIONS.has(message.act)) { rejectFrame('action_invalid'); return; }
      if (!authenticated && message.act !== 'ca_login') { rejectFrame('login_required'); return; }
      if ((message.act === 'ca_login' || IGNORED_ACTIONS.has(message.act))
          && !Object.hasOwn(message, 'device_id')) { rejectFrame('device_id_missing'); return; }
      for (const key of ['device_id', 'imei']) {
        if (!Object.hasOwn(message, key)) continue;
        if (typeof message[key] !== 'string') { rejectFrame(key === 'device_id' ? 'device_id_type' : 'imei_type'); return; }
        if (message[key] !== config.deviceId) { rejectFrame(key === 'device_id' ? 'device_id_mismatch' : 'imei_mismatch'); return; }
      }
      // This is an explicit no-op after login and identity validation. Do not
      // forward, fabricate an ACK, or renew the telemetry/idle heartbeat.
      if (IGNORED_ACTIONS.has(message.act)) return;
      // Forward canonical JSON so gateway and Java upstream see identical values,
      // including when an incoming object repeats a JSON property name.
      const text = JSON.stringify(message);
      const size = Buffer.byteLength(text);
      if (size > limits.maxPayload) { observe('ws_frame_rejected', 'payload'); cleanup(1009); return; }
      observe('ws_action_validated', message.act);
      if (!authenticated) {
        observe('ws_first_frame', 'accepted');
        authenticated = true;
        clearTimeout(authTimer);
        connect();
      }
      touch();
      if (upstream.readyState === WebSocket.OPEN) { send(upstream, text, false, message.act); return; }
      if (upstream.readyState !== WebSocket.CONNECTING || queued.length >= 8 || queuedBytes + size > limits.maxQueued) {
        observe('ws_frame_rejected', 'queue'); cleanup(1009); return;
      }
      queued.push({ text, act: message.act }); queuedBytes += size;
    });
  }

  server.on('upgrade', (request, socket, head) => {
    observe('ws_upgrade', 'received');
    const deny = (reason, status) => { observe('ws_upgrade_result', reason); return rejectUpgrade(socket, status); };
    if (closing) return deny('closing');
    if (request.method !== 'GET') return deny('method');
    if (!websocketPaths.has(request.url)) return deny('path');
    if (bridges.size >= limits.maxConnections) return deny('capacity', 429);
    if (!allowUpgrade()) return deny('rate', 429);
    let accepted = false;
    wsServer.handleUpgrade(request, socket, head, client => {
      accepted = true; observe('ws_upgrade_result', 'accepted'); bridge(client);
    });
    if (!accepted) observe('ws_upgrade_result', 'handshake');
  });

  return {
    async listen() {
      await new Promise((resolve, reject) => {
        server.once('error', reject);
        server.listen(config.listenPort, config.listenHost, () => { server.off('error', reject); resolve(); });
      });
      return server.address();
    },
    async close() {
      closing = true;
      for (const abort of pendingHttp) abort.abort();
      for (const handle of [...bridges]) handle.close();
      const stopped = new Promise(resolve => server.close(resolve));
      server.closeAllConnections();
      await stopped;
      await new Promise(resolve => wsServer.close(resolve));
    },
  };
}
