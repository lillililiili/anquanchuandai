import { blockedOperations } from './person-device-runtime.js';
export function authHeaders() { return {}; }
export function clearAuth() {}
export function saveAuth() { throw Error('隔离验收入口不能登录或保存凭据'); }
export async function authFetch(url) {
  const path = String(url).split('?')[0];
  blockedOperations.value = [...blockedOperations.value.slice(-5), `已阻止 ${path}`];
  return new Response(JSON.stringify({ message: '隔离验收：设备服务不可用，未发送实际请求' }), { status: 503, headers: { 'Content-Type': 'application/json' } });
}
