import {isIP} from 'node:net';
import {timingSafeEqual} from 'node:crypto';
import {createDeviceGateway} from '../device-gateway/gateway.mjs';
import {createBeltDeviceGateway} from '../belt-device-gateway/gateway.mjs';

const tokenPattern = /^[A-Za-z0-9_-]{43}$/;
function credential(value) {
  return typeof value === 'string' && tokenPattern.test(value)
    && Buffer.from(value, 'base64url').toString('base64url') === value;
}
function integer(value, fallback, min, max, name) {
  const result = value ?? fallback;
  if (!Number.isSafeInteger(result) || result < min || result > max) throw new Error(`Invalid ${name}.`);
  return result;
}
function origin(value, protocols) {
  let url;
  try { url = new URL(value); } catch { throw new Error('Invalid configured origin.'); }
  if (!protocols.includes(url.protocol) || url.origin !== value || url.username || url.password)
    throw new Error('An origin without path or credentials is required.');
  return url;
}
function privateHost(host) {
  if (/^[a-z][a-z0-9-]{0,62}$/.test(host)) return true; // Docker service names, no public DNS suffix.
  if (isIP(host) !== 4) return false;
  const [a,b] = host.split('.').map(Number);
  return a === 127 || a === 10 || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168);
}

export function validateClusterConfig(input, {testOnly = false} = {}) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) throw new Error('Invalid cluster gateway configuration.');
  const allowed = new Set(['listenHost','listenPort','upstreamOrigin','publicOrigin','nodeId','adminToken','devices',
    'healthPollMillis','healthTimeoutMillis','drainTimeoutMillis','limits','mediaControlOrigin','mediaSigningKey','deviceWebsocketOrigin']);
  if (Object.keys(input).some(key => !allowed.has(key))) throw new Error('Unknown cluster gateway field.');
  if (!['0.0.0.0','127.0.0.1'].includes(input.listenHost)) throw new Error('Invalid listener address.');
  if (!/^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$/.test(input.nodeId ?? '')) throw new Error('An explicit node identity is required.');
  if (!credential(input.adminToken)) throw new Error('A 32-byte management credential is required.');
  const upstream = origin(input.upstreamOrigin, ['http:']);
  if (!privateHost(upstream.hostname) || (['127.0.0.1','localhost'].includes(upstream.hostname) && upstream.port === '18084'))
    throw new Error('Use an isolated private paired backend.');
  const publicUrl = origin(input.publicOrigin, ['https:']);
  if (isIP(publicUrl.hostname.replace(/^\[|\]$/g,'')) || !publicUrl.hostname.includes('.')
      || /\.(invalid|test|local|localhost)$/.test(publicUrl.hostname)) throw new Error('A public HTTPS origin is required.');
  const deviceWebsocketOrigin = input.deviceWebsocketOrigin ?? input.publicOrigin.replace(/^https:/,'wss:');
  if (origin(deviceWebsocketOrigin, ['ws:','wss:']).hostname !== publicUrl.hostname) throw new Error('Device WebSocket host must match the public host.');
  if ((input.mediaControlOrigin || input.mediaSigningKey)
      && (input.mediaControlOrigin !== input.publicOrigin || !credential(input.mediaSigningKey)))
    throw new Error('Media signing requires the same HTTPS origin and a 32-byte key.');
  if (!Array.isArray(input.devices) || input.devices.length < 1 || input.devices.length > 100000) throw new Error('Explicit device credentials are required.');
  const ids = new Set(), tokens = new Set(), prefixes = new Set();
  const devices = input.devices.map(device => {
    if (!device || Object.keys(device).some(key => !['deviceId','pathToken'].includes(key))
        || !/^[A-Za-z0-9_-]{1,64}$/.test(device.deviceId ?? '') || !credential(device.pathToken)
        || ids.has(device.deviceId) || tokens.has(device.pathToken) || prefixes.has(device.pathToken.slice(0,24)))
      throw new Error('Device identities and route credentials must be valid and unique.');
    ids.add(device.deviceId); tokens.add(device.pathToken); prefixes.add(device.pathToken.slice(0,24));
    return Object.freeze({...device});
  });
  const limitBounds = {maxConnections:[1000,100000],upgradesPerMinute:[1200,1000000],
    requestsPerMinute:[6000,1000000],messagesPerSecond:[20,1000]};
  if (input.limits != null && (typeof input.limits !== 'object' || Array.isArray(input.limits)
      || Object.keys(input.limits).some(key => !Object.hasOwn(limitBounds,key)))) throw new Error('Unknown runtime limit.');
  const runtimeLimits = Object.fromEntries(Object.entries(limitBounds).map(([key,[fallback,max]]) =>
    [key,integer(input.limits?.[key],fallback,1,max,key)]));
  return Object.freeze({...input, devices:Object.freeze(devices), runtimeLimits:Object.freeze(runtimeLimits), deviceWebsocketOrigin,
    listenPort:integer(input.listenPort,8080,testOnly?0:1,65535,'listener port'),
    healthPollMillis:integer(input.healthPollMillis,1000,testOnly?10:250,30000,'health interval'),
    healthTimeoutMillis:integer(input.healthTimeoutMillis,1500,testOnly?10:100,10000,'health timeout'),
    drainTimeoutMillis:integer(input.drainTimeoutMillis,30000,testOnly?0:1000,300000,'drain timeout')});
}

function reply(response,status,body) {
  response.writeHead(status,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','Connection':'close'});
  response.end(JSON.stringify(body));
}
export function createClusterGateway(kind,input,{testOnly = false} = {}) {
  if (!['helmet','belt'].includes(kind)) throw new Error('Gateway kind must be helmet or belt.');
  const config = validateClusterConfig(input,{testOnly});
  let ready = false, draining = false, closed = false, healthTimer, drainTimer, healthAbort;
  const accepting = () => ready && !draining && !closed;
  const management = (request,response) => {
    if (!request.url?.startsWith('/internal/')) return false;
    if (request.method === 'GET' && request.url === '/internal/gateway/live') reply(response,200,{live:true});
    else if (request.method === 'GET' && request.url === '/internal/gateway/ready') reply(response,accepting()?200:503,{ready:accepting(),draining});
    else if (request.method === 'POST' && request.url === '/internal/gateway/drain') {
      const supplied = Buffer.from(request.headers['x-cluster-admin-token'] ?? '');
      const expected = Buffer.from(config.adminToken);
      if (supplied.length !== expected.length || !timingSafeEqual(supplied,expected)) reply(response,403,{accepted:false});
      else {
        if (!draining) { draining = true; drainTimer = setTimeout(() => gateway.disconnectDevices(),config.drainTimeoutMillis); drainTimer.unref(); }
        reply(response,202,{accepted:true,draining:true});
      }
    } else reply(response,404,{error:'Unavailable'});
    return true;
  };
  const create = kind === 'helmet' ? createDeviceGateway : createBeltDeviceGateway;
  const gateway = create(input,{testOnly,configure:() => config,accepting,management});
  async function probe() {
    healthAbort = new AbortController();
    const timeout = setTimeout(() => healthAbort.abort(),config.healthTimeoutMillis);
    try {
      const response = await fetch(config.upstreamOrigin+'/internal/cluster/ready',{
        signal:healthAbort.signal,redirect:'error',headers:{Accept:'application/json'}});
      ready = false;
      if (response.status !== 200) await response.body?.cancel();
      else {
        const chunks = []; let bytes = 0;
        for await (const chunk of response.body) {
          bytes += chunk.length;
          if (bytes > 4096) throw new Error('Invalid readiness response.');
          chunks.push(chunk);
        }
        ready = JSON.parse(Buffer.concat(chunks).toString('utf8'))?.ready === true;
      }
    } catch { ready = false; }
    finally {
      clearTimeout(timeout);
      if (!closed) { healthTimer = setTimeout(probe,config.healthPollMillis); healthTimer.unref(); }
    }
  }
  return {
    async listen() { const address = await gateway.listen(); await probe(); return address; },
    async close() { closed = true; ready = false; clearTimeout(healthTimer); clearTimeout(drainTimer); healthAbort?.abort(); await gateway.close(); }
  };
}
