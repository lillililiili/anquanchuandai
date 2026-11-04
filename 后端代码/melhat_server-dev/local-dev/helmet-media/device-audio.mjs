import fs from 'node:fs';
import { createHash } from 'node:crypto';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

export const AUDIO_MAX_BYTES = 32 * 1024 * 1024;
export const AUDIO_MAX_SECONDS = 600;
const execute = promisify(execFile);
const invalid = code => Object.assign(new Error(code), { status: 415, code });

// Device firmware may name MediaRecorder AMR/3GP output .mp3. The submitted
// extension and Content-Type are not evidence of the actual audio format.
export function audioContainer(head) {
  if (head.subarray(0, 6).toString() === '#!AMR\n' || head.subarray(0, 9).toString() === '#!AMR-WB\n') return { demuxer: 'amr', extension: 'amr', mime: head[5] === 45 ? 'audio/amr-wb' : 'audio/amr' };
  if (head.subarray(4, 8).toString() === 'ftyp') return head.subarray(8, 12).toString().startsWith('3g') ? { demuxer: 'mov', extension: '3gp', mime: 'audio/3gpp' } : { demuxer: 'mov', extension: 'm4a', mime: 'audio/mp4' };
  if (head.subarray(0, 3).toString() === 'ID3' || head[0] === 255 && (head[1] & 224) === 224) return { demuxer: 'mp3', extension: 'mp3', mime: 'audio/mpeg' };
  throw invalid('UNSUPPORTED_AUDIO_CONTENT');
}

export function validateAudioProbe(result, container, maximum = AUDIO_MAX_SECONDS) {
  const streams = result?.streams ?? [], duration = Number(result?.format?.duration);
  if (streams.length !== 1 || streams[0]?.codec_type !== 'audio' || !Number.isFinite(duration) || duration <= 0 || duration > maximum) throw invalid('INVALID_AUDIO');
  const stream = streams[0], codecs = { mp3: ['mp3'], amr: ['amr_nb', 'amr_wb'], mov: ['amr_nb', 'amr_wb', 'aac'] }[container.demuxer];
  const rate = Number(stream.sample_rate);
  if (!codecs?.includes(stream.codec_name) || ![1, 2].includes(Number(stream.channels)) || !Number.isFinite(rate) || rate < 8000 || rate > 48000) throw invalid('UNSUPPORTED_AUDIO_CODEC');
  return { durationSeconds: duration, codec: stream.codec_name };
}

export async function prepareDeviceAudio(input, output, run = execute) {
  const size = (await fs.promises.stat(input)).size;
  if (!size || size > AUDIO_MAX_BYTES) throw invalid('INVALID_AUDIO_SIZE');
  const handle = await fs.promises.open(input, 'r'), head = Buffer.alloc(16);
  try { await handle.read(head, 0, head.length, 0); } finally { await handle.close(); }
  const container = audioContainer(head);
  // Force a known binary demuxer. No playlists, external protocols or MOV data
  // references are accepted, even if an uploaded filename says "mp3".
  const options = ['-protocol_whitelist', 'file,pipe', '-f', container.demuxer,
    ...(container.demuxer === 'mov' ? ['-enable_drefs', '0', '-use_absolute_path', '0'] : [])];
  try {
    const { stdout } = await run('ffprobe', ['-v', 'error', ...options, '-probesize', '5000000', '-analyzeduration', '5000000', '-show_entries', 'format=duration:stream=codec_type,codec_name,channels,sample_rate', '-of', 'json', input], { timeout: 30000, maxBuffer: 1024 * 1024, windowsHide: true });
    const info = validateAudioProbe(JSON.parse(stdout), container);
    await run('ffmpeg', ['-nostdin', '-hide_banner', '-loglevel', 'error', ...options, '-i', input, '-map', '0:a:0', '-vn', '-sn', '-dn', '-map_metadata', '-1', '-ac', '1', '-ar', '24000', '-c:a', 'libmp3lame', '-b:a', '64k', '-t', String(AUDIO_MAX_SECONDS), '-f', 'mp3', '-n', output], { timeout: 45000, maxBuffer: 1024 * 1024, windowsHide: true });
    const converted = await run('ffprobe', ['-v', 'error', '-protocol_whitelist', 'file,pipe', '-f', 'mp3', '-show_entries', 'format=duration:stream=codec_type,codec_name,channels,sample_rate', '-of', 'json', output], { timeout: 15000, maxBuffer: 1024 * 1024, windowsHide: true });
    const playable = validateAudioProbe(JSON.parse(converted.stdout), { demuxer: 'mp3' }, AUDIO_MAX_SECONDS + 1);
    if (Math.abs(playable.durationSeconds - info.durationSeconds) > 1) throw invalid('AUDIO_DURATION_MISMATCH');
    // Windows requires a writable handle for fsync/FlushFileBuffers.
    const saved = await fs.promises.open(output, 'r+'); try { await saved.sync(); } finally { await saved.close(); }
    const hash = createHash('sha256'); for await (const chunk of fs.createReadStream(input)) hash.update(chunk);
    return { extension: container.extension, originalMime: container.mime, originalCodec: info.codec, originalSha256: hash.digest('hex'), durationSeconds: playable.durationSeconds, playbackMime: 'audio/mpeg', playbackVerified: true };
  } catch (error) {
    await fs.promises.unlink(output).catch(() => {});
    if (error?.status === 415) throw error;
    throw invalid('AUDIO_PROCESSING_FAILED'); // Do not expose file paths or decoder output.
  }
}
