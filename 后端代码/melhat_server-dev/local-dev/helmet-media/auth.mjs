import { createHash, createHmac, randomBytes, timingSafeEqual } from 'node:crypto';

export const sha256 = value => createHash('sha256').update(value).digest('hex');
export function signature(key, time, nonce, method, path, body = Buffer.alloc(0)) {
  return signatureFromDigest(key,time,nonce,method,path,sha256(body));
}
export function signatureFromDigest(key,time,nonce,method,path,digest) { return createHmac('sha256',key).update(`${time}\n${nonce}\n${method}\n${path}\n${digest}`).digest('hex'); }
export function signedDigestHeaders(key,method,path,digest,now=Date.now()) {
  const time=String(Math.floor(now/1000)),nonce=randomBytes(18).toString('base64url');
  return {'X-Media-Time':time,'X-Media-Nonce':nonce,'X-Media-Content-Sha256':digest,'X-Media-Signature':signatureFromDigest(key,time,nonce,method,path,digest)};
}
export function signedHeaders(key, method, path, body = Buffer.alloc(0), now = Date.now()) {
  const time = String(Math.floor(now / 1000)), nonce = randomBytes(18).toString('base64url');
  return { 'X-Media-Time': time, 'X-Media-Nonce': nonce,
    'X-Media-Signature': signature(key, time, nonce, method, path, body) };
}
function equal(a, b) { return typeof a === 'string' && a.length === b.length && timingSafeEqual(Buffer.from(a), Buffer.from(b)); }
export function verifier(key, now = Date.now) {
  const used = new Map();
  return (request, body, digest) => {
    const time = request.headers['x-media-time'], nonce = request.headers['x-media-nonce'], mac = request.headers['x-media-signature'];
    if (!/^\d{10,12}$/.test(time ?? '') || !/^[A-Za-z0-9_-]{16,80}$/.test(nonce ?? '') || !/^[a-f0-9]{64}$/.test(mac ?? '')) return false;
    const current = now();
    if (Math.abs(current / 1000 - Number(time)) > 90) return false;
    for (const [id, expires] of used) if (expires < current) used.delete(id);
    if (digest !== undefined && !/^[a-f0-9]{64}$/.test(digest)) return false;
    if (used.has(nonce) || used.size >= 10000 || !equal(mac, signatureFromDigest(key, time, nonce, request.method, request.url, digest ?? sha256(body)))) return false;
    used.set(nonce, current + 180000); return true;
  };
}
export function ticket(key, claims) {
  const data = Buffer.from(JSON.stringify(claims)).toString('base64url');
  return `${data}.${createHmac('sha256', key).update(data).digest('base64url')}`;
}
export function readTicket(key, token, now = Date.now()) {
  if (typeof token !== 'string' || token.length > 2048) return null;
  const [data, mac, extra] = token.split('.');
  if (extra || !data || !equal(mac, createHmac('sha256', key).update(data).digest('base64url'))) return null;
  try { const claims = JSON.parse(Buffer.from(data, 'base64url')); return claims.exp > now / 1000 ? claims : null; } catch { return null; }
}
