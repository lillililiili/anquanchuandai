import { createHash } from 'node:crypto';
import { appendFile, readFile } from 'node:fs/promises';

const MAX_REPORTS = 12;

function numeric(value, integer = false) {
  if (typeof value !== 'number' && typeof value !== 'string') return null;
  if (typeof value === 'string' && (value.length > 40 || !/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]?\d+)?$/i.test(value.trim()))) return null;
  const result = Number(value);
  return Number.isFinite(result) && (!integer || Number.isInteger(result)) ? result : null;
}

function coordinate(message, key, bound) {
  const value = numeric(message[key]);
  return { value, summary: { present: Object.hasOwn(message, key), finite: value !== null,
    nonzero: value !== null && value !== 0, inRange: value !== null && Math.abs(value) <= bound } };
}

function quality(value, min, max, integer = true) {
  const result = numeric(value, integer);
  return result !== null && result >= min && result <= max ? result : null;
}

// The only retained coordinate comparison state is a volatile hash, never written.
// Callbacks receive a fixed projection, never the incoming object or its identity.
export function createGpsDiagnostics(onReport) {
  if (typeof onReport !== 'function') return null;
  let observed = 0;
  function emit(summary) {
    try { Promise.resolve(onReport(summary)).catch(() => {}); } catch { /* Diagnostic only. */ }
  }
  return () => {
    let previous = null, ambiguousAck = false;
    const pending = [];
    return {
      report(message) {
        if (ambiguousAck || observed >= MAX_REPORTS) return;
        observed++;
        const x = coordinate(message, 'x_point', 90), y = coordinate(message, 'y_point', 180);
        const fingerprint = x.value !== null && y.value !== null
          ? createHash('sha256').update(JSON.stringify([x.value, y.value])).digest('hex') : null;
        pending.push({ observedAt: new Date().toISOString(),
          gps: quality(message.gps, 0, 32), gps_level: quality(message.gps_level, -1, 1),
          c_accuracy: quality(message.c_accuracy, 0, 10000000, false), c_startcount: quality(message.c_startcount, 0, 256),
          c_trust: quality(message.c_trust, 0, 4), x: x.summary, y: y.summary,
          coordinatesChanged: previous !== null && fingerprint !== null ? previous !== fingerprint : null,
          upstreamAck: false, upstreamAckReceived: false });
        previous = fingerprint;
      },
      ack(data) {
        if (!pending.length) return;
        try {
          const reply = JSON.parse(data.toString('utf8'));
          if (reply?.cmd === 'error') {
            // A parser error carries no original action. Stop correlation for
            // this connection rather than attach a later ACK to the wrong row.
            ambiguousAck = true;
            for (const summary of pending.splice(0)) emit(summary);
            return;
          }
          if (reply?.cmd !== 'ca_report_location' || typeof reply.status !== 'boolean') return;
          emit({ ...pending.shift(), upstreamAck: reply.status, upstreamAckReceived: true });
        } catch { /* Invalid upstream data still follows the normal forwarding path. */ }
      },
      close() { for (const summary of pending.splice(0)) emit(summary); },
    };
  };
}

// The CLI supplies one fixed ignored path. Existing lines count toward the cap,
// so restarting an enabled gateway cannot grow this diagnostic file past 12 rows.
export async function createGpsDiagnosticWriter(file) {
  let count;
  try { count = (await readFile(file, 'utf8')).split(/\r?\n/).filter(Boolean).length; }
  catch (error) { if (error.code !== 'ENOENT') return () => {}; count = 0; }
  let queued = Promise.resolve();
  return summary => {
    if (count >= MAX_REPORTS) return queued;
    count++;
    queued = queued.then(() => appendFile(file, JSON.stringify(summary) + '\n', { mode: 0o600 }))
      .catch(() => {});
    return queued;
  };
}
