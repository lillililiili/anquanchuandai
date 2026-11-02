import dgram from 'node:dgram';
import net from 'node:net';
import { open, mkdir, lstat, unlink } from 'node:fs/promises';
import { join } from 'node:path';
import { spawn } from 'node:child_process';

const MAX_BYTES = 256 * 1024 * 1024;
const MAX_DURATION = 5 * 60 * 1000;
const MAX_QUEUED_BYTES = 8 * 1024 * 1024;
const MAX_CAPTURES = 4;
let activeCaptures = 0;

function payloadOf(packet, expectedSsrc) {
  if (packet.length < 12 || packet[0] >>> 6 !== 2 || (packet[1] & 127) !== 96 || packet.readUInt32BE(8) !== expectedSsrc) return null;
  let offset = 12 + (packet[0] & 15) * 4;
  if (offset > packet.length) return null;
  if (packet[0] & 16) {
    if (offset + 4 > packet.length) return null;
    offset += 4 + packet.readUInt16BE(offset + 2) * 4;
    if (offset > packet.length) return null;
  }
  let end = packet.length;
  if (packet[0] & 32) {
    const padding = packet.at(-1);
    if (!padding || padding > end - offset) return null;
    end -= padding;
  }
  if (end <= offset) return null;
  return { sequence: packet.readUInt16BE(2), payload: packet.subarray(offset, end) };
}

function convertToMp4(ffmpegPath, psPath, mp4Path) {
  return new Promise(resolve => {
    // No shell or untrusted arguments. Video stays unchanged; audio becomes browser-compatible AAC.
    let child;
    let settled = false;
    let timedOut = false;
    let timer;
    const finish = error => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve(error);
    };
    try {
      child = spawn(ffmpegPath, ['-hide_banner', '-loglevel', 'error', '-nostdin', '-n', '-protocol_whitelist', 'file', '-i', psPath,
        '-map', '0:v:0', '-map', '0:a:0?', '-c:v', 'copy', '-c:a', 'aac', '-b:a', '128k', '-movflags', '+faststart', mp4Path],
      { windowsHide: true, stdio: ['ignore', 'ignore', 'ignore'] });
    } catch {
      finish('FFmpeg could not start; original PS is retained.');
      return;
    }
    child.once('error', () => finish('FFmpeg could not start; original PS is retained.'));
    child.once('close', code => finish(timedOut ? 'FFmpeg exceeded 30 seconds; original PS is retained.' : code === 0 ? null : 'FFmpeg conversion failed; original PS is retained.'));
    timer = setTimeout(() => {
      timedOut = true;
      child.kill('SIGKILL');
    }, 30_000);
  });
}

/** Local simulator only: receives RTP PS on IPv4 loopback, without packet reordering. */
export async function createCapture({ directory, id, transport = 'UDP', ssrc, port = 0, ffmpegPath, onLimit } = {}) {
  if (typeof directory !== 'string' || !directory) throw new Error('Capture directory is required');
  if (typeof id !== 'string' || !/^[A-Za-z0-9_-]{1,80}$/.test(id)) throw new Error('Invalid capture ID');
  if (!['UDP', 'TCP'].includes(transport)) throw new Error('Invalid capture transport');
  if (!Number.isInteger(port) || port < 0 || port > 65535) throw new Error('Invalid capture port');
  if (!(typeof ssrc === 'number' || (typeof ssrc === 'string' && /^\d{1,10}$/.test(ssrc))) || !Number.isInteger(Number(ssrc)) || Number(ssrc) < 0 || Number(ssrc) > 0xffffffff) throw new Error('Invalid capture SSRC');
  if (ffmpegPath !== undefined && (typeof ffmpegPath !== 'string' || !ffmpegPath)) throw new Error('Invalid FFmpeg path');
  if (onLimit !== undefined && typeof onLimit !== 'function') throw new Error('Invalid onLimit callback');
  if (activeCaptures >= MAX_CAPTURES) throw new Error('At most four simultaneous local captures are allowed');
  activeCaptures++;

  const psFile = `${id}.ps`;
  const mp4File = `${id}.mp4`;
  const psPath = join(directory, psFile);
  const mp4Path = join(directory, mp4File);
  const metadataPath = join(directory, `${id}.json`);
  const info = { id, transport, port: 0, packets: 0, bytes: 0, lostPackets: 0, invalidPackets: 0,
    state: 'recording', startedAt: null, endedAt: null, psFile, mp4File: null, error: null };
  let metadata;
  let output;
  let outputClosed;
  let socket;
  let client;
  let bound = false;
  let createdPs = false;
  let lastSequence;
  let durationTimer;
  let closePromise;
  let limitReached = false;
  let fatalError = false;

  function fail(message) {
    fatalError = true;
    info.error = message;
    void close();
  }
  function stopAtLimit(reason) {
    if (limitReached || info.state !== 'recording') return;
    limitReached = true;
    info.error = `Capture stopped: ${reason}.`;
    void close();
    if (onLimit) void Promise.resolve().then(() => onLimit(reason)).catch(() => {});
  }
  function receive(packet) {
    if (info.state !== 'recording') return;
    const parsed = payloadOf(packet, Number(ssrc));
    if (!parsed) { info.invalidPackets++; return; }
    const delta = lastSequence === undefined ? 1 : (parsed.sequence - lastSequence + 65536) % 65536;
    // Drop duplicate and late packets rather than corrupting the append-only PS stream.
    // lostPackets records forward gaps; a late packet does not undo those gaps.
    if (delta === 0 || delta >= 32768) return;
    if (info.bytes + parsed.payload.length > MAX_BYTES) { stopAtLimit('size-limit'); return; }
    if (output.writableLength + parsed.payload.length > MAX_QUEUED_BYTES) { stopAtLimit('backpressure-limit'); return; }
    lastSequence = parsed.sequence;
    info.lostPackets += delta - 1;
    info.packets++;
    info.bytes += parsed.payload.length;
    const canContinue = output.write(parsed.payload);
    if (!canContinue) client?.pause();
    if (info.bytes === MAX_BYTES) stopAtLimit('size-limit');
  }
  function accept(connection) {
    if (info.state !== 'recording' || client || connection.remoteAddress !== '127.0.0.1') {
      connection.on('error', () => {});
      connection.destroy();
      return;
    }
    client = connection;
    let pending = Buffer.alloc(0);
    connection.setTimeout(30_000, () => connection.destroy());
    connection.on('error', () => {});
    connection.on('data', chunk => {
      pending = pending.length ? Buffer.concat([pending, chunk]) : chunk;
      let offset = 0;
      while (offset + 2 <= pending.length && info.state === 'recording') {
        const length = pending.readUInt16BE(offset);
        if (offset + 2 + length > pending.length) break;
        // RFC4571 permits zero-length null frames.
        if (length) receive(pending.subarray(offset + 2, offset + 2 + length));
        offset += length + 2;
      }
      pending = Buffer.from(pending.subarray(offset));
    });
    connection.on('close', () => {
      if (pending.length && info.state === 'recording') info.invalidPackets++;
      if (client === connection) client = undefined;
    });
  }
  async function stopSocket() {
    client?.destroy();
    if (!socket) return;
    await new Promise(resolve => {
      try { socket.close(() => resolve()); } catch { resolve(); }
    });
    bound = false;
  }
  function close() {
    if (closePromise) return closePromise;
    info.state = 'closing';
    info.endedAt = new Date().toISOString();
    clearTimeout(durationTimer);
    closePromise = (async () => {
      try {
        await stopSocket();
        if (output && !output.destroyed && !output.writableEnded) output.end();
        if (outputClosed) await outputClosed;
        if (fatalError) {
          info.state = 'error';
        } else if (!ffmpegPath || !info.bytes) {
          info.state = 'captured';
          info.error ??= !info.bytes ? 'No RTP media received; PS capture is empty.' : 'FFmpeg is not configured; original PS is available.';
        } else {
          const error = await convertToMp4(ffmpegPath, psPath, mp4Path);
          if (error) {
            info.state = 'error';
            info.error = error;
          } else {
            info.mp4File = mp4File;
            info.state = 'ready';
          }
        }
        await metadata.writeFile(JSON.stringify(info, null, 2) + '\n');
      } catch {
        info.state = 'error';
        info.error = 'Capture finalization or metadata write failed; original PS is retained.';
      } finally {
        await metadata?.close().catch(() => {});
        activeCaptures--;
      }
      return { ...info };
    })();
    return closePromise;
  }

  try {
    await mkdir(directory, { recursive: true });
    // Reserve the ID before creating its PS file. wx and FFmpeg -n prevent overwrites.
    for (const file of [psPath, mp4Path]) {
      try {
        await lstat(file);
        throw new Error('Capture output already exists');
      } catch (error) { if (error.code !== 'ENOENT') throw error; }
    }
    metadata = await open(metadataPath, 'wx');
    const file = await open(psPath, 'wx');
    createdPs = true;
    output = file.createWriteStream();
    outputClosed = new Promise(resolve => output.once('close', resolve));
    output.on('error', () => {
      fatalError = true;
      info.error = 'PS capture write failed.';
      if (bound) void close();
    });
    output.on('drain', () => client?.resume());
    socket = transport === 'UDP' ? dgram.createSocket('udp4') : net.createServer(accept);
    socket.on('error', () => { if (bound) fail('RTP listener failed.'); });
    if (transport === 'UDP') socket.on('message', (packet, remote) => { if (remote.address === '127.0.0.1') receive(packet); });
    await new Promise((resolve, reject) => {
      const onError = error => reject(error);
      socket.once('error', onError);
      const listening = () => { socket.off('error', onError); resolve(); };
      if (transport === 'UDP') socket.bind({ port, address: '127.0.0.1', exclusive: true }, listening);
      else socket.listen({ port, host: '127.0.0.1', exclusive: true, backlog: 1 }, listening);
    });
    bound = true;
    info.port = socket.address().port;
    info.startedAt = new Date().toISOString();
    durationTimer = setTimeout(() => stopAtLimit('duration-limit'), MAX_DURATION);
    durationTimer.unref();
    if (fatalError) void close();
    return { port: info.port, snapshot: () => ({ ...info }), close };
  } catch (error) {
    await stopSocket();
    if (output) { output.destroy(); await outputClosed; }
    await metadata?.close().catch(() => {});
    if (createdPs) await unlink(psPath).catch(() => {});
    if (metadata) await unlink(metadataPath).catch(() => {});
    activeCaptures--;
    throw error;
  }
}
