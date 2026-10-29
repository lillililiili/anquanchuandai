import net from 'node:net';

// ESL framing uses Content-Length; never split the event body on blank lines.
export function frameDecoder(onFrame) {
  let pending = Buffer.alloc(0);
  return chunk => {
    pending = Buffer.concat([pending, chunk]);
    if (pending.length > 2 * 1024 * 1024) throw new Error('ESL frame too large');
    while (true) {
      const split = pending.indexOf('\n\n'); if (split < 0) return;
      const headers = {};
      for (const line of pending.subarray(0, split).toString().split('\n')) {
        const colon = line.indexOf(':'); if (colon > 0) headers[line.slice(0, colon).trim().toLowerCase()] = line.slice(colon + 1).trim();
      }
      const length = Number(headers['content-length'] || 0);
      if (!Number.isSafeInteger(length) || length < 0 || length > 1024 * 1024) throw new Error('Invalid ESL frame');
      if (pending.length < split + 2 + length) return;
      const body = pending.subarray(split + 2, split + 2 + length).toString();
      pending = pending.subarray(split + 2 + length); onFrame(headers, body);
    }
  };
}
export function eslCommand(config, command) {
  if (/\r|\n/.test(command)) return Promise.reject(new Error('Invalid ESL command'));
  return new Promise((resolve, reject) => {
    let sent = false, done = false;
    const socket = net.createConnection({ host: config.eslHost ?? '127.0.0.1', port: config.eslPort ?? 8021 });
    const finish = (error, body) => { if (done) return; done = true; socket.destroy(); error ? reject(error) : resolve(body); };
    socket.setTimeout(7000, () => finish(new Error('ESL timeout')));
    socket.on('error', () => finish(new Error('ESL unavailable')));
    socket.on('close', () => { if (!done) finish(new Error('ESL disconnected')); });
    const decode = frameDecoder((headers, body) => {
      if (headers['content-type'] === 'auth/request') socket.write(`auth ${config.eslPassword}\n\n`);
      else if (!sent && headers['content-type'] === 'command/reply') {
        if (!headers['reply-text']?.startsWith('+OK')) return finish(new Error('ESL authentication failed'));
        sent = true; socket.write(`${command.startsWith('bgapi ') ? command : `api ${command}`}\n\n`);
      } else if (sent && command.startsWith('bgapi ') && headers['content-type'] === 'command/reply') {
        if (!headers['reply-text']?.startsWith('+OK')) return finish(new Error('ESL command rejected'));
        finish(null, headers['reply-text']);
      } else if (sent && headers['content-type'] === 'api/response') {
        if (body.startsWith('-ERR')) return finish(new Error('ESL command rejected'));
        finish(null, body);
      }
    });
    socket.on('data', chunk => { try { decode(chunk); } catch (error) { finish(error); } });
  });
}
export function subscribeEsl(config, onEvent) {
  let socket, retry, closed = false;
  const connect = () => {
    if (closed) return;
    socket = net.createConnection({ host: config.eslHost ?? '127.0.0.1', port: config.eslPort ?? 8021 });
    const decode = frameDecoder((headers, body) => {
      if (headers['content-type'] === 'auth/request') socket.write(`auth ${config.eslPassword}\n\n`);
      else if (headers['content-type'] === 'command/reply' && headers['reply-text']?.startsWith('+OK accepted'))
        socket.write('event json CHANNEL_ANSWER CHANNEL_HANGUP_COMPLETE CUSTOM\n\n');
      else if (headers['content-type'] === 'text/event-json') { try { onEvent(JSON.parse(body)); } catch { /* Invalid events cannot change state. */ } }
    });
    socket.on('data', data => { try { decode(data); } catch { socket.destroy(); } });
    socket.on('error', () => {});
    socket.on('close', () => { if (!closed) { retry = setTimeout(connect, 5000); retry.unref(); } });
  };
  connect(); return () => { closed = true; clearTimeout(retry); socket?.destroy(); };
}
