// Synthetic camera endpoint for local project integration, never a real-helmet acceptance source.
import { spawn } from 'node:child_process';
import { existsSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

export function ffmpegLocation() {
  const folder = join(dirname(fileURLToPath(import.meta.url)), '.local/tools/imageio_ffmpeg/binaries');
  const filename = existsSync(folder) && readdirSync(folder).find(x => /^ffmpeg.*\.exe$/.test(x));
  if (!filename) throw Error('Local integration FFmpeg is unavailable');
  return join(folder, filename);
}

export function createVideoSource({ ffmpegPath = ffmpegLocation(), onEvent = () => {} } = {}) {
  let child = null, generation = 0;
  const state = { synthetic: true, running: false, starts: 0, stops: 0, exitCode: null, error: null, video: 'H264 640x360 15fps', audio: 'AAC 48kHz synthetic 880Hz' };
  function stop() {
    generation++;
    if (child) { const old = child; child = null; old.kill('SIGTERM'); state.stops++; }
    state.running = false;
  }
  function start(pushUrl) {
    const url = new URL(pushUrl);
    if (url.protocol !== 'rtmp:' || url.hostname !== '127.0.0.1' || (url.port || '1935') !== '1935' || !/^\/helmet\/[a-f0-9]{32}$/.test(url.pathname) || !url.searchParams.get('token') || url.username || url.password)
      throw Error('Synthetic publisher accepts only the isolated local SRS ticket');
    stop(); const current = ++generation; state.error = null; state.exitCode = null;
    child = spawn(ffmpegPath, ['-hide_banner', '-loglevel', 'error', '-nostdin', '-re', '-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=15',
      '-re', '-f', 'lavfi', '-i', 'sine=frequency=880:sample_rate=48000', '-c:v', 'libx264', '-preset', 'ultrafast', '-tune', 'zerolatency',
      '-pix_fmt', 'yuv420p', '-g', '30', '-b:v', '500k', '-c:a', 'aac', '-b:a', '64k', '-f', 'flv', url.href],
    { windowsHide: true, stdio: ['ignore', 'ignore', 'ignore'] });
    state.running = true; state.starts++;
    child.once('error', () => { if (generation === current) { state.error = 'Synthetic publisher could not start'; state.running = false; onEvent({ ...state }); } });
    child.once('close', code => { if (generation === current) { state.exitCode = code; state.running = false; child = null; onEvent({ ...state }); } });
    onEvent({ ...state }); return { ...state };
  }
  function command(message) {
    if (message?.cmd === 'server_push_open_rtsp') return start(message.push_url);
    if (['server_push_stop_rtsp', 'server_push_close_rtsp'].includes(message?.cmd)) { stop(); onEvent({ ...state }); return { ...state }; }
    return null;
  }
  return { command, start, stop, snapshot: () => ({ ...state }) };
}
