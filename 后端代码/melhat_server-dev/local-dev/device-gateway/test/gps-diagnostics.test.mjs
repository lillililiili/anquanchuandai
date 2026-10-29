import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createGpsDiagnostics, createGpsDiagnosticWriter } from '../gps-diagnostics.mjs';

test('diagnostics are disabled by default and malformed coordinates remain boolean flags', () => {
  assert.equal(createGpsDiagnostics(), null);
  const rows = [], connection = createGpsDiagnostics(row => rows.push(row))();
  connection.report({ x_point: '', y_point: 'Infinity', gps: 'secret', c_accuracy: {}, c_trust: false });
  connection.ack(Buffer.from('{"cmd":"other","status":true}'));
  assert.equal(rows.length, 0);
  connection.close();
  assert.deepEqual(rows[0].x, { present: true, finite: false, nonzero: false, inRange: false });
  assert.deepEqual(rows[0].y, rows[0].x);
  assert.equal(rows[0].gps, null); assert.equal(rows[0].c_accuracy, null); assert.equal(rows[0].c_trust, null);
  assert.equal(rows[0].upstreamAck, false); assert.equal(rows[0].upstreamAckReceived, false);
  const next = createGpsDiagnostics(row => rows.push(row))();
  next.report({ x_point: 0, y_point: 181 }); next.close();
  assert.deepEqual(rows[1].x, { present: true, finite: true, nonzero: false, inRange: true });
  assert.deepEqual(rows[1].y, { present: true, finite: true, nonzero: true, inRange: false });
});

test('fixed-file writer appends at most 12 rows including previous runs and swallows write errors', async t => {
  const folder = await mkdtemp(path.join(tmpdir(), 'helmet-gps-diagnostic-test-'));
  assert.equal(path.dirname(path.resolve(folder)), path.resolve(tmpdir()));
  t.after(() => rm(folder, { recursive: true, force: true }));
  const file = path.join(folder, 'diagnostics.jsonl');
  const first = await createGpsDiagnosticWriter(file);
  await Promise.all(Array.from({ length: 5 }, () => first({ upstreamAck: true })));
  const restarted = await createGpsDiagnosticWriter(file);
  await Promise.all(Array.from({ length: 20 }, () => restarted({ upstreamAck: false })));
  const lines = (await readFile(file, 'utf8')).trim().split('\n').map(JSON.parse);
  assert.equal(lines.length, 12);
  assert.equal(lines.filter(row => row.upstreamAck).length, 5);
  const failing = await createGpsDiagnosticWriter(path.join(folder, 'missing', 'diagnostics.jsonl'));
  await assert.doesNotReject(() => failing({ upstreamAck: true }));
});
