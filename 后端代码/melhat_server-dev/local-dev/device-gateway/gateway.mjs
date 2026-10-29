import http from 'node:http';
import { WebSocket, WebSocketServer } from 'ws';
import { validateConfig } from './config.mjs';
import { createGpsDiagnostics } from './gps-diagnostics.mjs';
import { createMediaUpload } from './media-upload.mjs';
import { forwardBackup } from './backup-upload.mjs';

const DEFAULT_LIMITS = Object.freeze({
  maxPayload: 65536, maxBuffered: 262144, maxQueued: 65536,
  maxConnections: 4, messagesPerSecond: 20, upgradesPerMinute: 12,
  requestsPerMinute: 60, authTimeoutMs: 5000, upstreamTimeoutMs: 5000,
  idleTimeoutMs: 90000, closeTimeoutMs: 1000,
});
const ACTIONS = new Set(['ca_login', 'ca_report_location', 'ca_sos', 'ca_sip_sos', 'ca_upload_photo', 'upload_video_success', 'push_to_client', 'toggle_localrecord']);
const LOCAL_RECORD_SYNC_KEYS = new Set(['act', 'device_id', 'type']);
const QUERY_KEYS = new Set(['ctl', 'act', 'device_id', 'app_version', 'ic', 'ca_ver']);

function counter(max, period) {
  let count = 0, started = Date.now();
  return () => {
    if (Date.now() - started >= period) { started = Date.now(); count = 0; }
    return ++count <= max;
  };
}

function jsonReply(response, status, body) {
  response.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store', 'Connection': 'close', 'X-Content-Type-Options': 'nosniff' });
  response.end(JSON.stringify(body));
}
function failure(response, status, code = 'Unavailable') {
  jsonReply(response, status, { status: false, msg_code: code, msg: 'Device request unavailable' });
}
function rejectUpgrade(socket, status = 404) {
  socket.end(`HTTP/1.1 ${status} Rejected\r\nConnection: close\r\nContent-Length: 0\r\n\r\n`);
}

export function createDeviceGateway(input, { testOnly = false, limits: testLimits = {}, onGpsReport, mediaFetch } = {}) {
  const config = validateConfig(input, { testOnly });
  if (!testOnly && Object.keys(testLimits).length) throw new Error('Runtime limits are fixed.');
  if (!testOnly && mediaFetch) throw new Error('Runtime media transport is fixed.');
  const mediaUpload = createMediaUpload(config, mediaFetch);
  const limits = { ...DEFAULT_LIMITS, ...testLimits };
  const bootstrapPath = `/${config.pathToken}/api/index.php`;
  const uploadPath = `/${config.pathToken}/api/upload`;
  const websocketPath = `/${config.pathToken}/wsHat`;
  const allowRequest = counter(limits.requestsPerMinute, 60000);
  const allowUpgrade = counter(limits.upgradesPerMinute, 60000);
  const bridges = new Set();
  const pendingHttp = new Set();
  const startGpsDiagnostics = createGpsDiagnostics(onGpsReport);
  let closing = false;
  const wsServer = new WebSocketServer({ noServer: true, maxPayload: limits.maxPayload,
    perMessageDeflate: false, clientTracking: true });

  async function bootstrap(request, response) {
    const raw = request.url ?? '';
    const separator = raw.indexOf('?');
    const path = separator === -1 ? raw : raw.slice(0, separator);
    if (path !== bootstrapPath && path !== uploadPath) return failure(response, 404);
    if (!allowRequest()) return failure(response, 429);
    if (request.method === 'POST') {
      const rawQuery = separator === -1 ? '' : raw.slice(separator + 1);
      const allowedKeys=path===uploadPath?new Set(['device_id','X-Progress-ID','app_version','ic','ca_ver']):new Set([...QUERY_KEYS,'user_id']);
      if (rawQuery.length > 2048 || rawQuery.includes('#') || /%(?![0-9a-fA-F]{2})/.test(rawQuery)
        || rawQuery.split('&').some(p => !allowedKeys.has(p.slice(0, p.indexOf('='))))) return failure(response, 400);
      const query=new URLSearchParams(rawQuery);
      if(path===bootstrapPath&&query.get('ctl')==='lowcaps'&&query.get('act')==='ca_backup_data')return forwardBackup(request,response,query,config,jsonReply,failure);
      return mediaUpload(request, response, query, jsonReply, failure, path===uploadPath);
    }
    if(path===uploadPath) return failure(response,405);
    if (request.method !== 'GET') return failure(response, 405);
    const rawQuery = separator === -1 ? '' : raw.slice(separator + 1);
    // M6811_58 adds app_version, ic (bootdaemon property, not ICCID), and ca_ver
    // through RxHttp query encoding. Accept bounded property strings but never
    // forward or log them. Keys must still be literal, unique allowlisted names.
    const parts = rawQuery.split('&');
    if (rawQuery.length > 2048 || rawQuery.includes('#') || /%(?![0-9a-fA-F]{2})/.test(rawQuery)
        || parts.length < 3 || parts.length > 6 || parts.some(part => {
          const equals = part.indexOf('=');
          return equals < 1 || !QUERY_KEYS.has(part.slice(0, equals));
        })) return failure(response, 400);
    const query = new URLSearchParams(rawQuery);
    if ([...query.keys()].some(key => query.getAll(key).length !== 1)
        || [...query.values()].some(value => value.length > 256 || /[\u0000-\u001f\u007f-\u009f\ufffd]/.test(value))
        || query.getAll('ctl').length !== 1 || query.getAll('act').length !== 1
        || query.getAll('device_id').length !== 1 || query.get('ctl') !== 'config'
        || query.get('act') !== 'get_config' || query.get('device_id') !== config.deviceId
        || request.headers['transfer-encoding'] || Number(request.headers['content-length'] ?? 0) !== 0) {
      return failure(response, 400);
    }
    const abort = new AbortController();
    pendingHttp.add(abort);
    const timer = setTimeout(() => abort.abort(), limits.upstreamTimeoutMs);
    const onClosed = () => abort.abort();
    response.once('close', onClosed);
    try {
      const url = new URL('/api/index.php', config.upstreamOrigin);
      url.search = new URLSearchParams({ ctl: 'config', act: 'get_config', device_id: config.deviceId }).toString();
      const upstream = await fetch(url, { redirect: 'error', signal: abort.signal,
        headers: { Accept: 'application/json' } });
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
        api_url: `${config.publicOrigin}/${config.pathToken}/api/`,
        ws_url: `${config.publicOrigin.replace(/^https:/, 'wss:')}${websocketPath}` }) } };
      // This gateway has no authority to reset paired accessory configuration.
      delete rewritten.data.extra;
      if (!response.destroyed) jsonReply(response, 200, rewritten);
    } catch {
      if (!response.destroyed && !response.headersSent) failure(response, 502);
    } finally {
      clearTimeout(timer);
      response.off('close', onClosed);
      pendingHttp.delete(abort);
      abort.abort();
    }
  }

  const server = http.createServer({ maxHeaderSize: 8192 }, (request, response) => {
    if (closing) return failure(response, 503);
    void bootstrap(request, response).catch(() => {
      if (!response.destroyed && !response.headersSent) failure(response, 502);
    });
  });
  server.maxHeadersCount = 24;
  server.requestTimeout = 300000;
  server.headersTimeout = 5000;
  server.keepAliveTimeout = 1000;
  server.on('clientError', (_error, socket) => { if (socket.writable) rejectUpgrade(socket, 400); });

  function bridge(client) {
    const gpsDiagnostics = startGpsDiagnostics?.();
    let upstream, ended = false, authenticated = false, loginAccepted = false, queuedBytes = 0;
    let queued = [];
    const pendingReceipts = new Map();
    const allowMessage = counter(limits.messagesPerSecond, 1000);
    let idleTimer;
    const authTimer = setTimeout(() => cleanup(1008), limits.authTimeoutMs);
    const handle = { close: () => cleanup(1001) };
    bridges.add(handle);

    function touch() {
      clearTimeout(idleTimer);
      idleTimer = setTimeout(() => cleanup(1001), limits.idleTimeoutMs);
    }
    function cleanup(code = 1001) {
      if (ended) return;
      ended = true;
      clearTimeout(authTimer);
      clearTimeout(idleTimer);
      queued = []; queuedBytes = 0;
      try { gpsDiagnostics?.close(); } catch { /* Diagnostics must not affect forwarding. */ }
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
    function send(socket, data, binary = false) {
      const size = Buffer.byteLength(data);
      if (socket?.readyState !== WebSocket.OPEN || size > limits.maxPayload
          || socket.bufferedAmount + size > limits.maxBuffered) { cleanup(1009); return false; }
      socket.send(data, { binary }, error => { if (error) cleanup(1011); });
      return true;
    }
    function connect() {
      upstream = new WebSocket(`${config.upstreamOrigin.replace(/^http:/, 'ws:')}/wsHat`, {
        handshakeTimeout: limits.upstreamTimeoutMs, maxPayload: limits.maxPayload,
        perMessageDeflate: false, followRedirects: false,
      });
      upstream.on('error', () => cleanup(1011));
      upstream.on('close', () => cleanup());
      upstream.on('open', () => {
        if (ended) { upstream.terminate(); return; }
        const messages = queued; queued = []; queuedBytes = 0;
        for (const message of messages) if (!send(upstream, message)) break;
      });
      upstream.on('message', (data, binary) => {
        if (ended) return;
        if (binary) { cleanup(1003); return; }
        touch();
        try {
          const pushed = JSON.parse(data.toString());
          if (pushed?.cmd === 'ca_login') loginAccepted = pushed.status === true;
          if (['server_push_get_local_video_list', 'server_push_upload_video'].includes(pushed.cmd)
            && /^[A-Za-z0-9_-]{1,80}$/.test(pushed.talkback_id ?? '')) {
            for (const [key, deadline] of pendingReceipts) if (deadline < Date.now()) pendingReceipts.delete(key);
            if (pendingReceipts.size < 32) pendingReceipts.set(pushed.talkback_id, Date.now() + 300000);
          }
        } catch { /* Unknown backend messages are still forwarded unchanged. */ }
        send(client, data);
        try { gpsDiagnostics?.ack(data); } catch { /* Diagnostics must not affect forwarding. */ }
      });
    }
    client.on('error', () => cleanup(1011));
    client.on('close', () => cleanup());
    client.on('message', (data, binary) => {
      if (ended) return;
      if (binary || !allowMessage()) { cleanup(1008); return; }
      let message;
      try { message = JSON.parse(data.toString('utf8')); } catch { cleanup(1008); return; }
      if (!message || typeof message !== 'object' || Array.isArray(message)
          || !ACTIONS.has(message.act) || (!authenticated && message.act !== 'ca_login')
          || (message.act === 'ca_login' && message.device_id !== config.deviceId)
          || (Object.hasOwn(message, 'device_id') && message.device_id !== config.deviceId)) {
        cleanup(1008); return;
      }
      // M6811 sends this three-field state report immediately after receiving
      // non-null sip_info. It is not a request to change the recording setting.
      if (message.act === 'toggle_localrecord'
          && (!loginAccepted || message.device_id !== config.deviceId
            || !['0', '1'].includes(message.type)
            || Object.keys(message).some(key => !LOCAL_RECORD_SYNC_KEYS.has(key)))) {
        cleanup(1008); return;
      }
      if (message.act === 'push_to_client') {
        if (!(pendingReceipts.get(message.talkback_id) > Date.now()) || !message.res || typeof message.res.status !== 'boolean'
          || typeof message.res.msg !== 'string' || message.res.msg.length > 1024
          || (message.res.data != null && (!Array.isArray(message.res.data) || message.res.data.length > 500
            || message.res.data.some(f => typeof f?.file_name !== 'string' || f.file_name.length > 255 || !/^[A-Za-z0-9_-]{8,80}$/.test(f.file_md5 ?? ''))))) {
          cleanup(1008); return;
        }
        pendingReceipts.delete(message.talkback_id);
      }
      // Forward canonical JSON so gateway and Java upstream see identical values,
      // including when an incoming object repeats a JSON property name.
      const text = JSON.stringify(message);
      const size = Buffer.byteLength(text);
      if (size > limits.maxPayload) { cleanup(1009); return; }
      if (message.act === 'ca_report_location') {
        try { gpsDiagnostics?.report(message); } catch { /* Diagnostics must not affect forwarding. */ }
      }
      if (!authenticated) {
        authenticated = true;
        clearTimeout(authTimer);
        connect();
      }
      touch();
      if (upstream.readyState === WebSocket.OPEN) { send(upstream, text); return; }
      if (upstream.readyState !== WebSocket.CONNECTING || queued.length >= 8 || queuedBytes + size > limits.maxQueued) {
        cleanup(1009); return;
      }
      queued.push(text); queuedBytes += size;
    });
  }

  server.on('upgrade', (request, socket, head) => {
    if (closing || request.method !== 'GET' || request.url !== websocketPath) return rejectUpgrade(socket);
    if (bridges.size >= limits.maxConnections || !allowUpgrade()) return rejectUpgrade(socket, 429);
    wsServer.handleUpgrade(request, socket, head, client => bridge(client));
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
