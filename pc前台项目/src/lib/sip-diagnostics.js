// Only fixed event names, SIP methods and numeric status codes may leave this mapper.
// Never return log content, addresses, headers, credentials, SDP or error messages.
const reasons = new Map([
  ['No Contact header in response to REGISTER, dropping response.', 'register_contact_missing'],
  ['No Contact header pointing to us, dropping response', 'register_contact_mismatch'],
  ['Contact pointing to us is missing expires parameter, dropping response', 'register_expiry_missing'],
  ['Via sent-by in the response does not match UA Via host value. Dropping.', 'response_via_mismatch'],
  ['More than one Via header field present in the response. Dropping.', 'response_multiple_via'],
  ['Response missing mandatory header field. Dropping.', 'response_header_missing'],
  ['Message body length is lower than the value in Content-Length header field. Dropping.', 'response_body_short'],
  ['Failed to parse incoming message. Dropping.', 'response_parse_failed'],
  ['WebSocket closed unexpectedly', 'transport_closed'],
  ['WebSocket error occurred.', 'transport_error'],
  ['Exception thrown by onMessage callback', 'message_handler_failed'],
  ['Received message while not connected, discarding...', 'message_after_disconnect'],
  ['Unable to obtain credentials, cannot authenticate', 'credentials_unavailable'],
  ["challenge with Digest algorithm different than 'MD5', authentication aborted", 'digest_algorithm_unsupported'],
  ['challenge without Digest realm, authentication aborted', 'digest_realm_missing'],
  ['challenge without Digest nonce, authentication aborted', 'digest_nonce_missing'],
  ["challenge without Digest qop different than 'auth' or 'auth-int', authentication aborted", 'digest_qop_unsupported'],
  ['User agent client request timed out. Generating internal 408 Request Timeout.', 'transaction_timeout'],
  ['User agent client request transport error. Generating internal 503 Service Unavailable.', 'transaction_transport_error'],
]);
const methods = new Set(['REGISTER', 'INVITE', 'ACK', 'CANCEL', 'BYE', 'OPTIONS', 'INFO', 'NOTIFY', 'MESSAGE', 'UPDATE', 'PRACK', 'SUBSCRIBE', 'REFER']);

export function sipLogDiagnostic(content) {
  if (typeof content !== 'string') return null;
  if (reasons.has(content)) return { event: reasons.get(content) };
  if (/^(401|407) apparently in authentication loop, cannot authenticate$/.test(content)) return { event: 'authentication_loop' };
  if (/^(401|407) with wrong or missing challenge, cannot authenticate$/.test(content)) return { event: 'authentication_challenge_invalid' };
  const wire = /^(Sending WebSocket message|Received WebSocket (?:text|binary) message):\n\n([\s\S]*)$/.exec(content);
  if (!wire) return null;
  const message = wire[2], first = message.split(/\r?\n/, 1)[0];
  const response = /^SIP\/2\.0 ([1-6]\d\d)(?: |$)/.exec(first);
  const request = /^([A-Z]+) [^\r\n]+ SIP\/2\.0$/.exec(first);
  const cseq = /^CSeq:\s*\d+\s+([A-Z]+)\s*$/mi.exec(message);
  const method = response ? cseq?.[1] : request?.[1];
  if (!methods.has(method)) return null;
  return { event: 'wire', direction: wire[1].startsWith('Sending') ? 'sent' : 'received',
    method, ...(response ? { status: Number(response[1]) } : {}) };
}

export function sipRegistrationState(state) {
  return ['Initial', 'Registered', 'Unregistered', 'Terminated'].includes(state) ? state : 'unknown';
}
