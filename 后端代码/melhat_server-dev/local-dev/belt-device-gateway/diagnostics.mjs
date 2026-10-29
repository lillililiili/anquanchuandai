import fs from 'node:fs';
import path from 'node:path';

export const EVENT_REASONS = Object.freeze(Object.fromEntries(Object.entries({
  transport_connection: ['open'],
  http_request: ['received'],
  http_result: ['path', 'rate', 'method', 'parameters', 'action', 'identity_missing', 'identity_mismatch', 'closing', 'upstream_failure', 'ok', 'internal_failure', 'malformed_http'],
  http_upstream: ['connecting', 'connected', 'failed'],
  ws_upgrade: ['received'],
  ws_upgrade_result: ['path', 'method', 'closing', 'capacity', 'rate', 'accepted', 'handshake'],
  ws_first_frame: ['received', 'json_invalid', 'shape_invalid', 'action_invalid', 'login_required', 'device_id_missing', 'device_id_type', 'device_id_mismatch', 'imei_type', 'imei_mismatch', 'binary', 'rate', 'timeout', 'accepted'],
  ws_frame_rejected: ['json_invalid', 'shape_invalid', 'action_invalid', 'device_id_missing', 'device_id_type', 'device_id_mismatch', 'imei_type', 'imei_mismatch', 'binary', 'rate', 'payload', 'queue'],
  ws_upstream: ['connecting', 'connected', 'failed', 'closed'],
  ws_action_received: ['ca_login', 'ca_report_location', 'ca_sos', 'ca_sip_sos', 'getSettingWithDev', 'show_current_battery', 'unknown'],
  ws_action_validated: ['ca_login', 'ca_report_location', 'ca_sos', 'ca_sip_sos'],
  ws_action_forwarded: ['ca_login', 'ca_report_location', 'ca_sos', 'ca_sip_sos'],
  ws_login_forwarded: ['ok'],
  ws_login_response: ['true', 'false', 'invalid'],
  ws_location_response: ['true', 'false', 'invalid'],
  ws_sos_response: ['true', 'false', 'invalid'],
  ws_sip_sos_response: ['true', 'false', 'invalid'],
  ws_error_response: ['true', 'false', 'invalid'],
  ws_response_invalid: ['json_invalid', 'shape_invalid', 'cmd_unknown'],
  ws_session: ['client_closed', 'client_error', 'upstream_binary', 'idle', 'send_failed', 'backpressure', 'closing'],
}).map(([event, reasons]) => [event, Object.freeze(reasons)])));

const MAX_BYTES = 262144;
const MAX_FILES = 3;
const MAX_RATE = 50;
const BASENAME = 'belt-gateway-events.ndjson';
const noop = () => {};

function boundedInteger(value, maximum) {
  return Number.isSafeInteger(value) && value > 0 && value <= maximum;
}

function safeRecord(record) {
  if (!record || typeof record !== 'object' || Array.isArray(record)) return null;
  const output = {};
  // Do not invoke getters or toJSON, enumerate payloads, or serialize other fields.
  for (const key of ['time', 'event', 'reason', 'count']) {
    const descriptor = Object.getOwnPropertyDescriptor(record, key);
    if (!descriptor || !Object.hasOwn(descriptor, 'value')) return null;
    output[key] = descriptor.value;
  }
  const { time, event, reason, count } = output;
  if (typeof time !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(time)
      || !Number.isFinite(Date.parse(time)) || new Date(time).toISOString() !== time
      || typeof event !== 'string' || !Object.hasOwn(EVENT_REASONS, event)
      || typeof reason !== 'string' || !EVENT_REASONS[event].includes(reason)
      || !Number.isSafeInteger(count) || count < 1) return null;
  return output;
}

/**
 * A synchronous, fail-closed sink. Only canonical UTC time, an allowlisted
 * event/reason pair, and a positive integer count can reach disk. Counts are
 * preserved, so gaps after rate limiting remain visible in subsequent records.
 * Options can lower the hard retention/rate ceilings, never raise them.
 */
export function createPrivacyLog(directory, { maxBytes = MAX_BYTES, maxFiles = MAX_FILES, maxEventsPerSecond = MAX_RATE } = {}) {
  if (typeof directory !== 'string' || !directory
      || !boundedInteger(maxBytes, MAX_BYTES) || !boundedInteger(maxFiles, MAX_FILES)
      || !boundedInteger(maxEventsPerSecond, MAX_RATE)) return noop;

  let disabled = false;
  let window = -1;
  let writtenInWindow = 0;
  const root = path.resolve(directory);
  const paths = Array.from({ length: MAX_FILES }, (_, i) => path.join(root, BASENAME + (i ? `.${i}` : '')));

  function inspect() {
    const directoryStat = fs.lstatSync(root);
    if (!directoryStat.isDirectory() || directoryStat.isSymbolicLink()) throw new Error('Unsafe log directory');
    return paths.map(file => {
      let stat;
      try { stat = fs.lstatSync(file); } catch (error) {
        if (error.code === 'ENOENT') return null;
        throw error;
      }
      if (!stat.isFile() || stat.isSymbolicLink()) throw new Error('Unsafe log file');
      return stat;
    });
  }

  function enforceBounds(stats) {
    for (let i = 0; i < paths.length; i++) {
      if (stats[i] && (i >= maxFiles || stats[i].size > maxBytes)) {
        fs.unlinkSync(paths[i]);
        stats[i] = null;
      }
    }
  }

  try { enforceBounds(inspect()); } catch { return noop; }

  return function observe(record) {
    if (disabled) return;
    let line;
    // Invalid/untrusted records must neither escape nor disable healthy logging.
    try {
      const safe = safeRecord(record);
      if (!safe) return;
      line = JSON.stringify(safe) + '\n';
    } catch { return; }
    const bytes = Buffer.byteLength(line);
    if (bytes > maxBytes) return;
    const currentWindow = Math.floor(Date.now() / 1000);
    if (currentWindow !== window) { window = currentWindow; writtenInWindow = 0; }
    if (writtenInWindow >= maxEventsPerSecond) return;
    writtenInWindow++;

    let descriptor;
    try {
      const stats = inspect();
      enforceBounds(stats);
      if (stats[0] && stats[0].size + bytes > maxBytes) {
        if (stats[maxFiles - 1]) fs.unlinkSync(paths[maxFiles - 1]);
        for (let i = maxFiles - 2; i >= 0; i--) {
          if (stats[i]) fs.renameSync(paths[i], paths[i + 1]);
        }
      }
      const flags = fs.constants.O_WRONLY | fs.constants.O_APPEND | fs.constants.O_CREAT | (fs.constants.O_NOFOLLOW ?? 0);
      descriptor = fs.openSync(paths[0], flags, 0o600);
      if (!fs.fstatSync(descriptor).isFile()) throw new Error('Unsafe log file');
      fs.writeFileSync(descriptor, line, 'utf8');
    } catch {
      // Diagnostics must never break device traffic or leak raw IO errors.
      disabled = true;
    } finally {
      if (descriptor !== undefined) {
        try { fs.closeSync(descriptor); } catch { disabled = true; }
      }
    }
  };
}
