import { isIP } from 'node:net';

export const DEVICE_ID = '866652021714127';
export const DAILY_UPSTREAM = 'http://127.0.0.1:18084';
export const DEFAULTS = Object.freeze({
  listenHost: '127.0.0.1', listenPort: 18086,
  upstreamOrigin: DAILY_UPSTREAM,
  publicOrigin: 'https://configure-public-host.invalid',
  deviceId: DEVICE_ID,
});

export class ConfigError extends Error {}

export function validateConfig(input, { testOnly = false } = {}) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) throw new ConfigError('Invalid local configuration.');
  const keys = new Set([...Object.keys(DEFAULTS), 'pathToken', 'mediaControlOrigin', 'mediaSigningKey']);
  if (Object.keys(input).some(key => !keys.has(key))) throw new ConfigError('Unknown configuration field.');
  if (input.listenHost !== '127.0.0.1') throw new ConfigError('The gateway must bind only to loopback.');
  if (!Number.isInteger(input.listenPort) || input.listenPort < (testOnly ? 0 : 1) || input.listenPort > 65535) throw new ConfigError('Invalid loopback port.');
  if (input.deviceId !== DEVICE_ID) throw new ConfigError('This gateway is restricted to the registered helmet.');
  const token = input.pathToken;
  if (typeof token !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(token)
      || Buffer.from(token, 'base64url').length !== 32 || Buffer.from(token, 'base64url').toString('base64url') !== token) {
    throw new ConfigError('A locally generated 32-byte path credential is required.');
  }
  let publicUrl, upstream;
  try { publicUrl = new URL(input.publicOrigin); upstream = new URL(input.upstreamOrigin); }
  catch { throw new ConfigError('Invalid configured origin.'); }
  if (publicUrl.protocol !== 'https:' || publicUrl.origin !== input.publicOrigin
      || publicUrl.username || publicUrl.password || isIP(publicUrl.hostname)
      || publicUrl.hostname === 'localhost' || /\.(invalid|test|local|localhost)$/.test(publicUrl.hostname)) {
    throw new ConfigError('Set an actual public HTTPS origin before starting.');
  }
  if (!testOnly && input.upstreamOrigin !== DAILY_UPSTREAM) throw new ConfigError('Unexpected daily upstream.');
  if (testOnly && (upstream.protocol !== 'http:' || upstream.hostname !== '127.0.0.1'
      || upstream.origin !== input.upstreamOrigin || !upstream.port || upstream.port === '18084')) {
    throw new ConfigError('Tests must use an isolated loopback upstream, never the daily service.');
  }
  if (input.mediaControlOrigin || input.mediaSigningKey) {
    if (input.mediaControlOrigin !== input.publicOrigin || !/^[A-Za-z0-9_-]{43}$/.test(input.mediaSigningKey ?? ''))
      throw new ConfigError('Media upload requires the same reviewed HTTPS origin and its private signing key.');
  }
  return Object.freeze({ ...input });
}
