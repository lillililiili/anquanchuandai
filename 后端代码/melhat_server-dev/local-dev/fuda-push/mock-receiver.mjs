import http from 'node:http';
import { createHash, createHmac, timingSafeEqual } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { resolve, dirname } from 'node:path';
import { existsSync, readFileSync, statSync, mkdirSync, openSync, writeSync, fsyncSync, closeSync, ftruncateSync } from 'node:fs';

// Synthetic local commissioning only. The real receiver must persist its eventId uniqueness in SQL.
export function createReceiver({ appId, secretBase64, delayMillis = 0, dropFirstResponse = false, storageFile, handleOther }) {
  const secret = Buffer.from(secretBase64 ?? '', 'base64');
  if (!appId || secret.length !== 32) throw new Error('Provide a test AppId and a Base64-encoded 32-byte secret');
  const events = new Map(), nonces = new Map();
  let requests = 0, rejected = 0, duplicates = 0, storageFault = false;
  if (storageFile && existsSync(storageFile)) {
    try {
      if (statSync(storageFile).size > 64 * 1024 * 1024) throw Error();
      for (const line of readFileSync(storageFile, 'utf8').split('\n').filter(Boolean)) {
        const row = JSON.parse(line);
        if (!row.event?.eventId || !/^[a-f0-9]{64}$/.test(row.hash) || events.has(row.event.eventId)) throw Error();
        events.set(row.event.eventId, row);
      }
    } catch { throw Error('Receiver history cannot be loaded; preserve and inspect the history file'); }
  }
  const server = http.createServer(async (req, res) => {
    const reply = (status, code) => { if (status >= 400) rejected++; res.writeHead(status, { 'content-type': 'application/json' }); res.end(JSON.stringify({ code })); };
    try {
      if (req.method !== 'POST' || req.url !== '/receive') {
        if (handleOther) return await handleOther(req, res);
        return reply(404, 40401);
      }
      const chunks = []; let size = 0;
      for await (const part of req) {
        size += part.length;
        if (size > 65536) { reply(413, 41301); return; }
        chunks.push(part);
      }
      const body = Buffer.concat(chunks);
      const timestamp = req.headers['x-timestamp'], nonce = req.headers['x-nonce'], signature = req.headers['x-signature'];
      const seconds = Math.floor(Date.now() / 1000);
      if (req.headers['x-app-id'] !== appId || !/^\d{1,12}$/.test(timestamp ?? '') || Math.abs(seconds - Number(timestamp)) > 300
          || !/^[0-9a-f-]{36}$/i.test(nonce ?? '') || !/^[0-9a-f]{64}$/.test(signature ?? '')) return reply(401, 40101);
      const hash = createHash('sha256').update(body).digest('hex');
      const canonical = ['POST', req.url, appId, timestamp, nonce, hash].join('\n');
      const expected = createHmac('sha256', secret).update(canonical).digest();
      if (!timingSafeEqual(expected, Buffer.from(signature, 'hex'))) return reply(401, 40101);
      for (const [key, expires] of nonces) if (expires < seconds) nonces.delete(key);
      if (nonces.has(nonce.toLowerCase())) return reply(409, 40902);
      nonces.set(nonce.toLowerCase(), seconds + 600);
      const event = JSON.parse(body.toString('utf8'));
      if (!event || typeof event.eventId !== 'string' || !/^[A-Za-z0-9_-]{1,80}$/.test(event.eventId)
          || !['POSITION', 'STATUS', 'ALARM'].includes(event.eventType) || !event.data
          || typeof event.data !== 'object' || Array.isArray(event.data)) return reply(400, 40001);
      if (events.has(event.eventId) && events.get(event.eventId).hash !== hash) return reply(409, 40903);
      if (storageFault) return reply(503, 50301);
      if (events.has(event.eventId)) duplicates++;
      else {
        if (events.size >= 5000) return reply(507, 50701);
        const row = { hash, event, receivedAt: new Date().toISOString() };
        if (storageFile) {
          let fd, originalSize = 0;
          try {
            mkdirSync(dirname(storageFile), { recursive: true });
            const line = Buffer.from(JSON.stringify(row) + '\n');
            originalSize = existsSync(storageFile) ? statSync(storageFile).size : 0;
            if (originalSize + line.length > 64 * 1024 * 1024) return reply(507, 50701);
            fd = openSync(storageFile, existsSync(storageFile) ? 'r+' : 'wx+', 0o600);
            for (let offset = 0; offset < line.length;) {
              const written = writeSync(fd, line, offset, line.length - offset, originalSize + offset);
              if (written <= 0) throw Error('Incomplete write'); offset += written;
            }
            fsyncSync(fd);
          } catch {
            if (fd !== undefined) try { ftruncateSync(fd, originalSize); fsyncSync(fd); } catch { storageFault = true; }
            return reply(503, 50301);
          } finally { if (fd !== undefined) try { closeSync(fd); } catch { storageFault = true; } }
        }
        events.set(event.eventId, row);
      }
      requests++;
      if (delayMillis > 0) await new Promise(done => setTimeout(done, delayMillis));
      if (dropFirstResponse && requests === 1) { req.socket.destroy(); return; }
      reply(200, 0);
    } catch { if (!res.headersSent) reply(400, 40001); else res.destroy(); }
  });
  server.requestTimeout = 10000;
  return { server, events, get requests() { return requests; }, get rejected() { return rejected; }, get duplicates() { return duplicates; } };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const receiver = createReceiver({ appId: process.env.MOCK_APP_ID, secretBase64: process.env.MOCK_SECRET_BASE64,
    delayMillis: Number(process.env.MOCK_DELAY_MS || 0), dropFirstResponse: process.env.MOCK_DROP_FIRST_RESPONSE === 'true' });
  const port = Number(process.env.MOCK_PORT || 19091);
  receiver.server.listen(port, '127.0.0.1', () => console.log(`Synthetic receiver: http://127.0.0.1:${receiver.server.address().port}/receive`));
  for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => receiver.server.close());
}
