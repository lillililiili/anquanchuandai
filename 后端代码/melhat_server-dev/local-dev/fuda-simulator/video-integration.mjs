// Isolated local integration only. Uses the unchanged production media/GB classes.
// Private configuration, generated TLS keys, journals and evidence stay in .local.
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import https from 'node:https';
import { fileURLToPath } from 'node:url';
import { randomBytes } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { createServer } from '../helmet-media/server.mjs';
import { subscribeEsl } from '../helmet-media/esl.mjs';
import { configuration } from '../fuda-gb-bridge/config.mjs';
import { GbBridge } from '../fuda-gb-bridge/bridge.mjs';
import { MediaAdapter } from '../fuda-gb-bridge/media.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
export const directory = path.join(here, '.local', 'integration');
const file = name => path.join(directory, name);
const read = name => JSON.parse(fs.readFileSync(file(name), 'utf8'));
const write = (name, value) => {
  const target = file(name); fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, value, { mode: 0o600 });
};
const json = (name, value) => write(name, JSON.stringify(value, null, 2) + '\n');
const secret = () => randomBytes(32).toString('base64url');
const docker = args => {
  const result = spawnSync('docker', args, { windowsHide: true, stdio: 'pipe', encoding: 'utf8' });
  if (result.status !== 0) throw Error('Isolated Docker operation failed; inspect the named integration container.');
  return result.stdout.trim();
};

export function prepare() {
  fs.mkdirSync(directory, { recursive: true });
  if (!fs.existsSync(file('media-config.json'))) json('media-config.json', {
    mediaOrigin: 'https://127.0.0.1:19190', sharedKey: secret(), hookKey: secret(), eslPassword: secret(), turnSecret: secret(), zlmSecret: secret(),
    certificate: file('media-cert.pem'), srsOrigin: 'rtmp://127.0.0.1:1935', srsApi: 'http://127.0.0.1:11985',
    srsHttp: 'http://127.0.0.1:18096', zlmOrigin: 'http://127.0.0.1:19194', deviceId: 'FUDA-IT-HELMET-01',
  });
  const c = read('media-config.json');
  if (!fs.existsSync(c.certificate)) docker(['run', '--rm', '--name', 'fuda-sim-it-cert', '-v', `${directory}:/integration`, 'eclipse-temurin:21-jre-jammy',
    'openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '7', '-keyout', '/integration/media-key.pem', '-out', '/integration/media-cert.pem',
    '-subj', '/CN=Fuda local integration only', '-addext', 'subjectAltName=IP:127.0.0.1,DNS:localhost']);
  write('srs.conf', `listen 1935;\nmax_connections 30;\ndaemon off;\nsrs_log_tank console;\nsrs_log_level warn;\nhttp_api { enabled on; listen 1985; }\nhttp_server { enabled on; listen 8080; dir ./objs/nginx/html; }\nvhost __defaultVhost__ {\n hls { enabled on; hls_fragment 2; hls_window 10; hls_cleanup on; }\n http_hooks { enabled on; on_publish http://host.docker.internal:19191/internal/srs/${c.hookKey}; on_unpublish http://host.docker.internal:19191/internal/srs/${c.hookKey}; on_play http://host.docker.internal:19191/internal/srs/${c.hookKey}; }\n}\n`);
  write('zlm.ini', `[api]\napiDebug=0\nsecret=${c.zlmSecret}\n[general]\nlisten_ip=0.0.0.0\nmediaServerId=fuda-sim-it\nenableVhost=0\nmaxStreamWaitMS=5000\n[http]\nport=18194\nsslport=0\ndirMenu=0\nallow_ip_range=127.0.0.1,172.16.0.0-172.31.255.255,192.168.0.0-192.168.255.255\nrootPath=/tmp/empty-www\n[protocol]\nenable_audio=1\nadd_mute_audio=0\nenable_rtmp=1\nenable_rtsp=0\nenable_hls=0\nenable_mp4=0\nenable_ts=0\nenable_fmp4=0\n[rtmp]\nport=0\nsslport=0\n[rtsp]\nport=0\nsslport=0\n[rtp_proxy]\nport=0\n[rtc]\nport=0\ntcpPort=0\nsignalingPort=0\nsignalingSslPort=0\nicePort=0\niceTcpPort=0\n[srt]\nport=0\n[shell]\nport=0\n[hook]\nenable=0\n`);
  write('freeswitch/freeswitch.xml', `<?xml version="1.0"?>\n<document type="freeswitch/xml">\n<X-PRE-PROCESS cmd="set" data="domain=127.0.0.1"/>\n<section name="configuration">\n<X-PRE-PROCESS cmd="include" data="autoload_configs/*.xml"/>\n</section>\n<section name="dialplan"><context name="helmet"/></section><section name="directory"/></document>\n`);
  write('freeswitch/autoload_configs/modules.conf.xml', '<configuration name="modules.conf"><modules><load module="mod_console"/><load module="mod_commands"/><load module="mod_sofia"/><load module="mod_event_socket"/></modules></configuration>');
  write('freeswitch/autoload_configs/event_socket.conf.xml', `<configuration name="event_socket.conf"><settings><param name="listen-ip" value="127.0.0.1"/><param name="listen-port" value="18021"/><param name="password" value="${c.eslPassword}"/></settings></configuration>`);
  write('freeswitch/autoload_configs/sofia.conf.xml', '<configuration name="sofia.conf"><profiles><profile name="helmet"><settings><param name="sip-ip" value="127.0.0.1"/><param name="rtp-ip" value="127.0.0.1"/><param name="sip-port" value="15960"/><param name="context" value="helmet"/><param name="auth-calls" value="true"/><param name="accept-blind-reg" value="false"/><param name="manage-presence" value="false"/></settings></profile></profiles></configuration>');
  write('compose.yml', `name: fuda-sim-it-media\nservices:\n  srs:\n    container_name: fuda-sim-it-srs\n    image: ossrs/srs@sha256:2da6c730116ab231b6b514521b010828af5b577b3093dfae4186f2ca110fa06f\n    command: [./objs/srs, -c, /etc/it-srs.conf]\n    ports: ["127.0.0.1:1935:1935", "127.0.0.1:11985:1985", "127.0.0.1:18096:8080", "127.0.0.1:18194:18194"]\n    volumes: ["./srs.conf:/etc/it-srs.conf:ro"]\n    restart: "no"\n  zlm:\n    container_name: fuda-sim-it-zlm\n    image: zlmediakit/zlmediakit@sha256:3c98f76c84fe191b3f2411c7378a2b4f4838af4cb2939f12fe1d2c23912ccb26\n    network_mode: service:srs\n    entrypoint: [/opt/media/bin/MediaServer, -c, /etc/it-zlm.ini, -l, "2"]\n    volumes: ["./zlm.ini:/etc/it-zlm.ini:ro"]\n    restart: "no"\n`);
  console.log('Private integration config and TLS certificate prepared.');
}

export async function serveMedia() {
  const c = read('media-config.json');
  const { server, service } = createServer({ publicOrigin: 'https://127.0.0.1:19190', publicIp: '127.0.0.1', sipHost: '127.0.0.1',
    signingKey: c.sharedKey, hookKey: c.hookKey, eslPassword: c.eslPassword, turnSecret: c.turnSecret, eslHost: '127.0.0.1', eslPort: 18021,
    dataDir: file('media-state'), srsApi: c.srsApi, srsHttp: c.srsHttp, ttsOrigin: 'http://127.0.0.1:19192', browserOrigins: ['http://127.0.0.1:19091'] });
  const handler = server.listeners('request')[0];
  const traced = (req, res) => {
    const pathname = new URL(req.url, 'http://127.0.0.1').pathname;
    const route = pathname.startsWith('/internal/') ? pathname.split('/').slice(0, 3).join('/') + '/[private]' : pathname;
    res.once('finish', () => fs.appendFileSync(file('media-http-trace.jsonl'), JSON.stringify({ at: new Date().toISOString(), method: req.method, route, status: res.statusCode }) + '\n'));
    handler(req, res);
  };
  server.removeAllListeners('request'); server.on('request', traced);
  const secure = https.createServer({ key: fs.readFileSync(file('media-key.pem')), cert: fs.readFileSync(c.certificate) }, traced);
  // Docker Desktop changes loopback namespaces. Only the RTP destination is translated;
  // all API calls, tickets, stream validation and PS/RTP encoding remain real.
  const relay = http.createServer(async (req, res) => {
    try {
      if (req.method !== 'POST' || !/^\/index\/api\/(?:addStreamProxy|getMediaInfo|startSendRtp|stopSendRtp|delStreamProxy|close_streams)$/.test(req.url)) { res.writeHead(404); return res.end(); }
      const chunks = []; let size = 0;
      for await (const chunk of req) { size += chunk.length; if (size > 8192) throw Error('oversize'); chunks.push(chunk); }
      const body = new URLSearchParams(Buffer.concat(chunks).toString());
      if (body.get('secret') !== c.zlmSecret) { res.writeHead(401); return res.end(); }
      if (req.url.endsWith('/startSendRtp')) {
        if (body.get('dst_url') !== '127.0.0.1') throw Error('nonlocal');
        body.set('dst_url', 'host.docker.internal');
      }
      const reply = await fetch(`http://127.0.0.1:18194${req.url}`, { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body, signal: AbortSignal.timeout(6000) });
      res.writeHead(reply.status, { 'content-type': 'application/json' }); res.end(await reply.text());
    } catch { res.writeHead(502); res.end('{"code":-1,"error":"INTEGRATION_RELAY_UNAVAILABLE"}'); }
  });
  for (const [listener, port] of [[server, 19191], [secure, 19190], [relay, 19194]]) await new Promise((resolve, reject) => { listener.once('error', reject); listener.listen(port, '127.0.0.1', resolve); });
  const unsubscribe = subscribeEsl(service.config, e => service.handleEsl(e));
  const reaper = setInterval(() => service.reapExpired().catch(() => {}), 5000); reaper.unref();
  const close = () => { clearInterval(reaper); unsubscribe(); service.close(); for (const s of [server, secure, relay]) s.close(); };
  process.once('SIGINT', close); process.once('SIGTERM', close);
  console.log('Real local MediaService HTTPS 19190; SRS hook 19191; ZLM relay 19194.');
  return { service, close };
}

export async function serveBridge() {
  const c = read('media-config.json'), j = read('java-config.json'), sim = JSON.parse(fs.readFileSync(path.join(here, '.local', 'config.json'), 'utf8'));
  if (j.javaOrigin !== 'http://127.0.0.1:18095' || j.deviceId !== 'FUDA-IT-HELMET-01' || c.zlmOrigin !== 'http://127.0.0.1:19194' || c.srsOrigin !== 'rtmp://127.0.0.1:1935')
    throw Error('Integration bridge requires the isolated loopback Java/media endpoints and synthetic device');
  const config = configuration({ GB_ENABLED: 'true', GB_UPPER_IP: '127.0.0.1', GB_UPPER_PORT: '15061', GB_UPPER_ID: sim.upperId,
    GB_LOCAL_ID: sim.sipUsername, GB_LOCAL_IP: '127.0.0.1', GB_BIND_IP: '127.0.0.1', GB_LOCAL_PORT: '15060', GB_REALM: sim.realm,
    GB_PASSWORD: sim.sipPassword, GB_MEDIA_IP: '127.0.0.1', GB_MEDIA_PEERS: '127.0.0.1', GB_MEDIA_MIN_PORT: '1024', GB_MEDIA_MAX_PORT: '65535',
    GB_RTP_SOURCE_PORT: '31000', GB_CHANNELS_JSON: JSON.stringify([{ channelId: '34020000001320000001', deviceId: j.deviceId ?? c.deviceId, deviceType: 'HELMET', name: 'Project synthetic helmet - real media chain' }]),
    GB_JAVA_ORIGIN: j.javaOrigin, GB_JAVA_SECRET: j.javaSecret, GB_ZLM_ORIGIN: c.zlmOrigin, GB_ZLM_SECRET: c.zlmSecret, GB_SRS_ORIGIN: c.srsOrigin,
    GB_REQUIRE_AUDIO: 'true', GB_HEARTBEAT_SECONDS: '10', GB_SOURCE_TIMEOUT_MS: '30000', GB_JOURNAL: file('gb-journal.json') });
  const bridge = new GbBridge(config, new MediaAdapter(config), { log: code => console.log(new Date().toISOString(), code) });
  await bridge.start();
  write('bridge.pid', String(process.pid));
  let closing;
  const close = () => closing ??= (async () => {
    clearInterval(stopTimer); await bridge.close();
    if (fs.existsSync(file('bridge.pid')) && fs.readFileSync(file('bridge.pid'), 'utf8').trim() === String(process.pid)) fs.unlinkSync(file('bridge.pid'));
  })();
  const stopTimer = setInterval(() => {
    if (fs.existsSync(file('bridge.stop')) && fs.readFileSync(file('bridge.stop'), 'utf8').trim() === String(process.pid)) {
      fs.unlinkSync(file('bridge.stop')); void close();
    }
  }, 500);
  process.once('SIGINT', close); process.once('SIGTERM', close);
  console.log('Existing project GB bridge started against local simulator; awaiting registration; synthetic input only.');
  return bridge;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    if (process.argv[2] === 'prepare') prepare();
    else if (process.argv[2] === 'media') await serveMedia();
    else if (process.argv[2] === 'bridge') await serveBridge();
    else throw Error('Usage: node video-integration.mjs prepare|media|bridge');
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
