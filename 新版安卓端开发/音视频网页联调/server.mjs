import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';
import { WebSocketServer, WebSocket } from 'ws';
import agoraToken from 'agora-token';
import { createBusinessLab, streamRandomVideo } from './business-lab.mjs';

export const accounts = [
  { id: 'dispatch', name: '调度员', role: '调度中心', initials: '调', color: 'blue' },
  { id: 'helmet-001', name: '安全帽 001', role: '一号测试设备', initials: '01', color: 'green' },
  { id: 'helmet-002', name: '安全帽 002', role: '二号测试设备', initials: '02', color: 'orange' },
  { id: 'inspector', name: '巡检员', role: '移动测试端', initials: '巡', color: 'purple' },
];
const accountIds = new Set(accounts.map(a => a.id));
const assets = {
  '/business': ['business.html', 'text/html; charset=utf-8'],
  '/business.js': ['business.js', 'text/javascript; charset=utf-8'],
  '/business.css': ['business.css', 'text/css; charset=utf-8'],
  '/alarms': ['alarms.html', 'text/html; charset=utf-8'],
  '/alarms.js': ['alarms.js', 'text/javascript; charset=utf-8'],
  '/alarms.css': ['alarms.css', 'text/css; charset=utf-8'],
  '/': ['index.html', 'text/html; charset=utf-8'],
  '/app.js': ['app.js', 'text/javascript; charset=utf-8'],
  '/rtc.js': ['rtc.js', 'text/javascript; charset=utf-8'],
  '/source.js': ['source.js', 'text/javascript; charset=utf-8'],
  '/styles.css': ['styles.css', 'text/css; charset=utf-8'],
  '/icon.svg': ['icon.svg', 'image/svg+xml'],
};

export function createLab({ ringMs = 45000, connectMs = 30000, reconnectMs = 15000, iceServers = [], appId = '', appCertificate = '', backendUrl = '' } = {}) {
  const businessLab = createBusinessLab({ backendUrl, ringMs });
  const agoraConfigured = /^[a-f\d]{32}$/i.test(appId) && /^[a-f\d]{32}$/i.test(appCertificate);
  const clients = new Map();
  const calls = new Map();
  const history = [];
  const peers = new Set();
  const pendingPlatform = new Map();
  function send(ws, data) {
    if (ws?.readyState === WebSocket.OPEN) ws.send(JSON.stringify(data));
  }
  function activeFor(id) {
    return [...calls.values()].find(c => c.from === id || c.to === id);
  }
  function view(call) {
    const { timer, ready, platform, ...data } = call;
    return data;
  }
  async function endPlatform(call, platform) {
    try {
      const response = await fetch(`${backendUrl}/api/v1/calls/${encodeURIComponent(platform.id)}/end`, {
        method: 'POST', headers: platform.headers, signal: AbortSignal.timeout(8000),
      });
      const result = await response.json();
      if (!response.ok || (result.code !== undefined && result.code !== 200)) throw new Error('平台未确认结束');
      send(clients.get(call.to), { type: 'platform-sync', ok: true, callId: call.id });
    } catch {
      send(clients.get(call.to), { type: 'platform-sync', ok: false, callId: call.id });
    }
  }
  function credentials(call, account) {
    if (!agoraConfigured) throw new Error('请先在 .env 配置有效的 AGORA_APP_ID 和 AGORA_APP_CERTIFICATE');
    const uid = account === call.from ? 1001 : 1002;
    return {
      agoraAppId: appId, channelName: call.channelName, agoraUid: uid,
      agoraToken: agoraToken.RtcTokenBuilder.buildTokenWithUid(appId, appCertificate, call.channelName, uid, agoraToken.RtcRole.PUBLISHER, 3600, 3600),
      expiresAt: new Date(Date.now() + 3600000).toISOString(), demo: false, video: call.kind === 'video',
    };
  }
  function broadcastRoster() {
    const users = accounts.map(a => ({ ...a, online: clients.has(a.id), busy: !!activeFor(a.id), sn: clients.get(a.id)?.sn || '' }));
    for (const ws of peers) send(ws, { type: 'roster', accounts: users });
  }
  function notify(call, type = 'call') {
    for (const id of [call.from, call.to]) send(clients.get(id), { type, call: view(call) });
  }
  function finish(call, reason, endedBy = null) {
    if (!calls.has(call.id)) return;
    clearTimeout(call.timer);
    call.state = 'ended';
    call.reason = reason;
    call.endedBy = endedBy;
    call.endedAt = Date.now();
    calls.delete(call.id);
    history.unshift(view(call));
    if (history.length > 60) history.pop();
    notify(call);
    broadcastRoster();
    if (call.external) {
      if (call.platform) void endPlatform(call, call.platform);
      else {
        // The callee can reject while the original Java start request is still returning.
        pendingPlatform.set(call.channelName, call);
        const timer = setTimeout(() => pendingPlatform.delete(call.channelName), 60000);
        timer.unref();
      }
    }
  }
  function setDeadline(call, ms, reason) {
    clearTimeout(call.timer);
    call.timer = setTimeout(() => finish(call, reason), ms);
  }
  const server = http.createServer(async (req, res) => {
    const url = new URL(req.url, 'http://localhost');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Referrer-Policy', 'same-origin');
    res.setHeader('Cache-Control', 'no-store');
    const json = (status, data) => res.writeHead(status, { 'Content-Type': 'application/json' }).end(JSON.stringify(data));
    if (await businessLab(req, res, url)) return;
    // Optional Android API gateway. Business auth stays in Java; its response is forwarded unchanged.
    // Capturing only the creating request allows test-device hangup/reject to end that exact session.
    if (url.pathname.startsWith('/api/v1/') || ['/login', '/logout', '/captchaImage', '/getInfo'].includes(url.pathname)) {
      if (!backendUrl) { json(503, { code: 503, msg: '尚未配置 BACKEND_URL' }); return; }
      try {
        let body = '';
        for await (const chunk of req) { body += chunk; if (Buffer.byteLength(body) > 2 * 1024 * 1024) throw new Error('请求过大'); }
        const headers = { 'Content-Type': req.headers['content-type'] || 'application/json' };
        if (req.headers.authorization) headers.Authorization = req.headers.authorization;
        if (req.headers['x-site-id']) headers['X-Site-Id'] = req.headers['x-site-id'];
        const upstream = await fetch(`${backendUrl}${url.pathname}${url.search}`, {
          method: req.method, headers, body: ['GET', 'HEAD'].includes(req.method) ? undefined : body,
          signal: AbortSignal.timeout(25000), redirect: 'manual',
        });
        const raw = await upstream.text();
        if (url.pathname === '/api/v1/calls' && req.method === 'POST' && upstream.ok) {
          try {
            const result = JSON.parse(raw), session = result.data;
            if ((result.code === undefined || result.code === 200) && session?.id && session?.channelName) {
              const call = [...calls.values()].find(c => c.channelName === session.channelName && c.external) || pendingPlatform.get(session.channelName);
              if (call && headers.Authorization) {
                const platform = { id: String(session.id), headers };
                if (calls.has(call.id)) call.platform = platform;
                else { pendingPlatform.delete(session.channelName); void endPlatform(call, platform); }
              }
            }
          } catch {}
        }
        res.writeHead(upstream.status, { 'Content-Type': upstream.headers.get('content-type') || 'application/json' }).end(raw);
      } catch { json(502, { code: 502, msg: '测试工具无法连接业务后端，请检查 BACKEND_URL 和 Docker 状态' }); }
      return;
    }
    // HeadbandService-compatible test vendor. Only configured device identities are callable.
    if (url.pathname === '/api/token' && req.method === 'GET') {
      json(200, { code: 200, data: { accessToken: 'call-lab-local', tokenType: 'Bearer', expireTime: 7200 } }); return;
    }
    if ((url.pathname === '/api/agora/token' || url.pathname === '/api/monitor/call/end') && req.method === 'POST') {
      try {
        let raw = '';
        for await (const chunk of req) { raw += chunk; if (raw.length > 8192) throw new Error('请求过大'); }
        const body = JSON.parse(raw || '{}');
        if (url.pathname.endsWith('/end')) {
          const call = [...calls.values()].find(c => c.channelName === body.channelName && c.external);
          if (call) finish(call, 'hangup', call.from);
          json(200, { code: 200, data: true }); return;
        }
        if (!agoraConfigured) throw new Error('尚未配置声网测试凭证，不能连接安卓');
        if (!Array.isArray(body.helmetSnList) || body.helmetSnList.length !== 1) throw new Error('测试工具只支持单设备通话');
        const sn = body.helmetSnList[0];
        const target = [...clients.values()].find(c => c.sn === sn);
        if (!target) throw new Error('该 SN 的模拟安全帽未上线，请先在网页绑定设备编号');
        if (activeFor(target.account)) throw new Error('模拟安全帽正在通话');
        const id = randomUUID();
        const call = {
          id, from: `android-${id}`, to: target.account, external: true,
          // The current Java gateway only sends helmetSnList, not the requested video flag.
          kind: 'video', transport: 'agora', channelName: `lab-${id}`,
          state: 'ringing', createdAt: Date.now(), connectedAt: null,
          sources: {}, ready: new Set(), timer: null,
        };
        const cred = credentials(call, call.from);
        calls.set(id, call);
        setDeadline(call, ringMs, 'no_answer');
        notify(call); broadcastRoster();
        json(200, { code: 200, data: cred });
      } catch (error) { json(400, { code: 400, message: error.message }); }
      return;
    }
    if (url.pathname.startsWith('/api/intercom/end/') && req.method === 'PUT') {
      const sn = decodeURIComponent(url.pathname.slice('/api/intercom/end/'.length));
      const target = [...clients.values()].find(c => c.sn === sn);
      const call = target && activeFor(target.account);
      if (call?.external) finish(call, 'hangup', call.from);
      json(200, { code: 200, data: true }); return;
    }
    if (url.pathname === '/video/stream') {
      return streamRandomVideo(req, res);
    }
    if (req.method !== 'GET') { res.writeHead(405).end(); return; }
    if (url.pathname === '/health') {
      res.writeHead(200, { 'Content-Type': 'application/json' }).end(JSON.stringify({ ok: true, users: clients.size, calls: calls.size }));
      return;
    }
    if (url.pathname === '/config') {
      json(200, { accounts, iceServers, ringMs, connectMs, agoraConfigured });
      return;
    }
    if (url.pathname === '/agora-sdk.js') {
      const sdk = await readFile(new URL('./node_modules/agora-rtc-sdk-ng/AgoraRTC_N-production.js', import.meta.url));
      res.writeHead(200, { 'Content-Type': 'text/javascript; charset=utf-8' }).end(sdk); return;
    }
    const asset = assets[url.pathname];
    if (!asset) { res.writeHead(404).end('Not found'); return; }
    try {
      const data = await readFile(new URL(`./public/${asset[0]}`, import.meta.url));
      res.writeHead(200, { 'Content-Type': asset[1] }).end(data);
    } catch {
      res.writeHead(500).end('Unable to load page');
    }
  });
  const wss = new WebSocketServer({ noServer: true, maxPayload: 96 * 1024 });
  server.on('upgrade', (req, socket, head) => {
    // These identities deliberately have no passwords. Limit browser access to this site.
    let sameOrigin = !req.headers.origin;
    try { sameOrigin ||= new URL(req.headers.origin).host === req.headers.host; } catch {}
    if (req.url !== '/signal' || !sameOrigin) { socket.destroy(); return; }
    wss.handleUpgrade(req, socket, head, ws => wss.emit('connection', ws));
  });
  wss.on('connection', ws => {
    peers.add(ws);
    ws.alive = true;
    ws.on('pong', () => { ws.alive = true; });
    const fail = (message, request) => send(ws, { type: 'error', message, request });
    ws.on('message', raw => {
      let message;
      try { message = JSON.parse(raw); } catch { fail('消息格式不正确'); return; }
      if (!message || typeof message !== 'object') { fail('消息格式不正确'); return; }
      const { type } = message;
      if (type === 'login') {
        const id = message.account;
        if (!accountIds.has(id)) { fail('请选择有效的测试账号', type); return; }
        if (ws.account && activeFor(ws.account)) { fail('请先结束当前通话，再切换账号', type); return; }
        if (clients.has(id) && clients.get(id) !== ws) { fail('该账号已在另一个窗口在线，请选择其他账号', type); return; }
        const sn = String(message.sn || '').trim();
        if (sn && !/^[a-z\d_-]{1,64}$/i.test(sn)) { fail('设备 SN 只能包含字母、数字、下划线和短横线', type); return; }
        if (sn && [...clients.values()].some(c => c !== ws && c.sn === sn)) { fail('该设备 SN 已被另一个窗口绑定', type); return; }
        if (ws.account && clients.get(ws.account) === ws) clients.delete(ws.account);
        ws.account = id;
        ws.sn = sn;
        clients.set(id, ws);
        send(ws, { type: 'welcome', account: id, sn, history: history.filter(c => c.from === id || c.to === id) });
        broadcastRoster();
        return;
      }
      if (!ws.account || clients.get(ws.account) !== ws) { fail('请先选择账号', type); return; }
      if (type === 'dial') {
        if (activeFor(ws.account)) { fail('当前已有通话', type); return; }
        if (!['audio', 'video'].includes(message.kind)) { fail('无效的通话类型', type); return; }
        if (!accountIds.has(message.to) || message.to === ws.account) { fail('请选择其他测试账号', type); return; }
        if (!clients.has(message.to)) { fail('对方不在线，请先打开对端窗口', type); return; }
        if (activeFor(message.to)) { fail('对方正在通话中', type); return; }
        const transport = message.transport === 'webrtc' ? 'webrtc' : 'agora';
        if (transport === 'agora' && !agoraConfigured) { fail('请先配置声网凭证，或选择网页自检模式', type); return; }
        const id = randomUUID();
        const call = {
          id, from: ws.account, to: message.to, kind: message.kind, transport, channelName: `lab-${id}`,
          state: 'ringing', createdAt: Date.now(), connectedAt: null,
          sources: { [ws.account]: message.source === 'synthetic' ? 'synthetic' : 'device' },
          ready: new Set(), timer: null,
        };
        calls.set(call.id, call);
        setDeadline(call, ringMs, 'no_answer');
        notify(call);
        broadcastRoster();
        return;
      }
      const call = calls.get(message.callId);
      if (!call || (call.from !== ws.account && call.to !== ws.account)) {
        // Late ICE/end messages are normal after hangup; never forward them to another call.
        return;
      }
      if (type === 'accept') {
        if (call.to !== ws.account || call.state !== 'ringing') return;
        call.state = 'connecting';
        call.sources[ws.account] = message.source === 'synthetic' ? 'synthetic' : 'device';
        setDeadline(call, connectMs, 'connection_timeout');
        notify(call);
      } else if (type === 'credentials') {
        if (call.transport !== 'agora' || call.state === 'ringing') return;
        try { send(ws, { type: 'credentials', callId: call.id, credentials: credentials(call, ws.account) }); }
        catch (error) { fail(error.message, type); }
      } else if (type === 'reject') {
        if (call.to === ws.account && call.state === 'ringing') finish(call, 'rejected', ws.account);
      } else if (type === 'end') {
        const reason = message.reason === 'media_error' ? 'media_error' : message.reason === 'connection_failed' ? 'connection_failed' : call.state === 'ringing' ? 'cancelled' : 'hangup';
        finish(call, reason, ws.account);
      } else if (type === 'signal') {
        if (call.state === 'ringing' || call.transport !== 'webrtc') return;
        const data = message.data;
        if (!data || !['offer', 'answer', 'candidate'].includes(data.type)) return;
        if (data.type === 'offer' && ws.account !== call.from) return;
        if (data.type === 'answer' && ws.account !== call.to) return;
        const other = call.from === ws.account ? call.to : call.from;
        send(clients.get(other), { type: 'signal', callId: call.id, data });
      } else if (type === 'media-state') {
        if (!['connecting', 'connected', 'reconnecting'].includes(call.state)) return;
        if (message.connected === true) {
          call.ready.add(ws.account);
          if (call.external) call.ready.add(call.from); // Browser reports only after observing Android's RTC media.
          if (call.ready.size === 2) {
            clearTimeout(call.timer);
            call.state = 'connected';
            call.connectedAt ||= Date.now();
            notify(call);
          }
        } else {
          call.ready.delete(ws.account);
          if (call.state === 'connected') {
            call.state = 'reconnecting';
            setDeadline(call, reconnectMs, 'connection_failed');
            notify(call);
          }
        }
      }
    });
    ws.on('close', () => {
      peers.delete(ws);
      if (ws.account && clients.get(ws.account) === ws) {
        const call = activeFor(ws.account);
        clients.delete(ws.account);
        if (call) finish(call, 'peer_left', ws.account);
        else broadcastRoster();
      }
    });
    ws.on('error', () => {});
    broadcastRoster();
  });
  const heartbeat = setInterval(() => {
    for (const ws of peers) {
      if (!ws.alive) ws.terminate();
      else { ws.alive = false; ws.ping(); }
    }
  }, 10000);
  heartbeat.unref();
  return {
    server,
    async close() {
      clearInterval(heartbeat);
      for (const call of calls.values()) clearTimeout(call.timer);
      for (const ws of peers) ws.terminate();
      await new Promise(resolve => wss.close(resolve));
      if (server.listening) await new Promise(resolve => server.close(resolve));
    },
  };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  let iceServers;
  try {
    iceServers = JSON.parse(process.env.ICE_SERVERS_JSON || '[]');
    if (!Array.isArray(iceServers)) throw new Error('not an array');
  } catch { throw new Error('ICE_SERVERS_JSON must be a JSON array'); }
  const lab = createLab({ iceServers, appId: process.env.AGORA_APP_ID || '', appCertificate: process.env.AGORA_APP_CERTIFICATE || '', backendUrl: (process.env.BACKEND_URL || '').replace(/\/$/, '') });
  const port = Number(process.env.PORT || 18766);
  lab.server.listen(port, '0.0.0.0', () => console.log(`Call Lab listening on http://localhost:${port}`));
  for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => lab.close().then(() => process.exit(0)));
}
