import { readFile, stat, rename, unlink } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { join } from 'node:path';
import { spawn } from 'node:child_process';
import dgram from 'node:dgram';
import net from 'node:net';
import { GbBridge } from '../fuda-gb-bridge/bridge.mjs';

async function sample(directory, ffmpegPath) {
  if (!ffmpegPath) throw Error('未找到 FFmpeg，先配置 FFMPEG_PATH 后再使用视频演示');
  const filename = join(directory, 'synthetic-source.ps');
  try { if ((await stat(filename)).size > 0) return filename; } catch {}
  const temporary = filename + '.' + randomUUID() + '.tmp';
  try { await new Promise((resolve, reject) => {
    const process = spawn(ffmpegPath, ['-hide_banner', '-loglevel', 'error', '-nostdin', '-y',
      '-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=15', '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=44100',
      '-t', '6', '-c:v', 'libx264', '-profile:v', 'baseline', '-pix_fmt', 'yuv420p', '-preset', 'ultrafast',
      '-g', '15', '-c:a', 'mp2', '-b:a', '128k', '-f', 'mpeg', temporary], { windowsHide: true, stdio: 'ignore' });
    const timer = setTimeout(() => process.kill(), 20000);
    process.once('error', () => { clearTimeout(timer); reject(Error('FFmpeg 无法启动')); });
    process.once('close', code => { clearTimeout(timer); code === 0 ? resolve() : reject(Error('生成合成视频失败')); });
  });
    await rename(temporary, filename);
  } finally { await unlink(temporary).catch(() => {}); }
  return filename;
}

// A synthetic lower platform exercises the SAME existing GbBridge, without device or Java services.
export async function createDemoBridge({ upper, config, directory, ffmpegPath }) {
  const filename = await sample(directory, ffmpegPath);
  const bytes = await readFile(filename), jobs = new Map();
  let bridge;
  const media = {
    async recover() {}, async cleanupOrphans() {},
    async device() { return { online: true }; }, async prepare() {}, async renew() {},
    async start(row) {
      const controller = new AbortController(), m = row.media;
      const socket = m.tcp ? net.createConnection({ host: '127.0.0.1', port: m.port }) : dgram.createSocket('udp4');
      socket.on('error', () => controller.abort());
      if (m.tcp) await new Promise((done, fail) => { socket.once('connect', done); socket.once('error', fail); });
      const job = { socket, controller }; jobs.set(row.callId, job);
      job.done = (async () => {
        const chunkSize = 1200, chunks = Math.ceil(bytes.length / chunkSize), interval = 6000 / chunks;
        for (let offset = 0, seq = 0; offset < bytes.length && !controller.signal.aborted; offset += chunkSize, seq++) {
          const payload = bytes.subarray(offset, offset + chunkSize), packet = Buffer.alloc(12 + payload.length);
          packet[0] = 0x80; packet[1] = 96; packet.writeUInt16BE(seq & 65535, 2);
          packet.writeUInt32BE(Math.floor(seq * interval * 90) >>> 0, 4); packet.writeUInt32BE(Number(m.ssrc), 8); payload.copy(packet, 12);
          if (m.tcp) {
            const length = Buffer.alloc(2); length.writeUInt16BE(packet.length);
            await new Promise((done, fail) => socket.write(Buffer.concat([length, packet]), e => e ? fail(e) : done()));
          } else await new Promise((done, fail) => socket.send(packet, m.port, '127.0.0.1', e => e ? fail(e) : done()));
          await new Promise(done => setTimeout(done, Math.max(1, interval)));
        }
      })().catch(() => {}).finally(() => {
        if (!controller.signal.aborted) setTimeout(() => bridge.finish(row, true).catch(() => {}), 20);
      });
    },
    async release(row) {
      const job = jobs.get(row.callId); if (!job) return true;
      job.controller.abort(); await job.done;
      if (row.media.tcp) job.socket.destroy(); else try { job.socket.close(); } catch {}
      jobs.delete(row.callId); return true;
    }
  };
  bridge = new GbBridge({ enabled: true, transport: 'UDP', upperIp: '127.0.0.1', upperPort: upper.port,
    upperId: config.upperId, realm: config.realm, username: config.sipUsername, password: config.sipPassword,
    localId: config.sipUsername, localIp: '127.0.0.1', bindIp: '127.0.0.1', localPort: 0,
    channels: [{ channelId: '34020000001320000001', deviceId: 'DEMO-HELMET-01', deviceType: 'HELMET', name: '模拟安全帽 · 彩条与测试音' }],
    mediaPeers: ['127.0.0.1'], mediaMinPort: 1024, mediaMaxPort: 65535, mediaIp: '127.0.0.1', rtpSourcePort: 30000,
    maxSessions: 1, maxSessionMs: 60000, sourceTimeoutMs: 5000, ackTimeoutMs: 5000, transactionMs: 5000, t1: 100,
    registerSeconds: 60, heartbeatSeconds: 10, heartbeatFailures: 3, leaseRenewMs: 20000 }, media);
  try {
    await bridge.start();
    const deadline = Date.now() + 6000;
    while (!bridge.registered) {
      if (Date.now() > deadline) throw Error('模拟设备注册失败');
      await new Promise(done => setTimeout(done, 25));
    }
    await upper.catalog();
    return bridge;
  } catch (e) { await bridge.close(); throw e; }
}
