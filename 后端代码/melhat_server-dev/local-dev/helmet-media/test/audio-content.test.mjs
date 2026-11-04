import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { audioContainer, validateAudioProbe, prepareDeviceAudio } from '../device-audio.mjs';

test('audio detection uses file contents and validates stream/duration, never the mp3 extension', () => {
  assert.equal(audioContainer(Buffer.from('#!AMR\n')).mime, 'audio/amr');
  assert.equal(audioContainer(Buffer.from('#!AMR-WB\n')).mime, 'audio/amr-wb');
  assert.equal(audioContainer(Buffer.from('\0\0\0\x18ftyp3gp6')).mime, 'audio/3gpp');
  assert.equal(audioContainer(Buffer.from('\0\0\0\x18ftypisom')).mime, 'audio/mp4');
  assert.throws(() => audioContainer(Buffer.from('#EXTM3U\nhttps://host/private')), /UNSUPPORTED_AUDIO_CONTENT/);
  const valid = { streams: [{ codec_type: 'audio', codec_name: 'amr_nb', channels: 1, sample_rate: '8000' }], format: { duration: '2' } };
  assert.equal(validateAudioProbe(valid, { demuxer: 'amr' }).codec, 'amr_nb');
  for(const sample_rate of [undefined,'not-a-rate','Infinity',0])assert.throws(()=>validateAudioProbe({...valid,streams:[{...valid.streams[0],sample_rate}]},{demuxer:'amr'}),/UNSUPPORTED_AUDIO_CODEC/);
  for (const changed of [{ ...valid, streams: [...valid.streams, { codec_type: 'video' }] }, { ...valid, format: { duration: '601' } }, { ...valid, format: { duration: 'NaN' } }, { ...valid, streams: [{ ...valid.streams[0], codec_name: 'unknown' }] }]) assert.throws(() => validateAudioProbe(changed, { demuxer: 'amr' }));
});

let available = true;
try { execFileSync('ffmpeg', ['-version'], { stdio: 'ignore', timeout: 5000, windowsHide: true }); execFileSync('ffprobe', ['-version'], { stdio: 'ignore', timeout: 5000, windowsHide: true }); } catch { available = false; }
if (process.env.REQUIRE_AUDIO_TOOLCHAIN === '1' && !available) throw Error('Required real audio toolchain is missing');

test('actual AMR, AAC/3GP and MP3 decode to a verified playable derivative while original bytes remain', { skip: !available }, async t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'helmet-audio-content-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const mp3 = path.join(directory, 'source.mp3'), gp = path.join(directory, 'source.3gp');
  for (const [file, codec, format] of [[mp3, 'libmp3lame', 'mp3'], [gp, 'aac', '3gp']]) execFileSync('ffmpeg', ['-nostdin', '-v', 'error', '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=8000', '-t', '0.4', '-ac', '1', '-c:a', codec, '-f', format, file], { timeout: 15000 });
  const amr = path.join(directory, 'mislabelled.mp3');
  fs.writeFileSync(amr, Buffer.concat([Buffer.from('#!AMR\n'), ...Array.from({ length: 20 }, () => Buffer.from([0x3c, ...Array(31).fill(0)]))]));
  for (const [index, file] of [mp3, gp, amr].entries()) {
    const before = fs.readFileSync(file), out = path.join(directory, `play-${index}.mp3`);
    const result = await prepareDeviceAudio(file, out);
    assert.equal(result.playbackVerified, true); assert.equal(result.playbackMime, 'audio/mpeg');
    assert.equal(result.originalSha256, createHash('sha256').update(before).digest('hex'));
    assert.deepEqual(fs.readFileSync(file), before); assert.ok(fs.statSync(out).size > 100);
    assert.ok(result.durationSeconds > 0 && result.durationSeconds < 2);
    if (file === amr) assert.equal(result.originalMime, 'audio/amr');
  }
  const broken = path.join(directory, 'broken.mp3'), failed = path.join(directory, 'failed.mp3');
  fs.writeFileSync(broken, 'ID3not-real-audio');
  await assert.rejects(prepareDeviceAudio(broken, failed), /AUDIO_PROCESSING_FAILED|INVALID_AUDIO/);
  assert.equal(fs.existsSync(failed), false);
});
