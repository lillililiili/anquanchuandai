const TOKEN = "wearable-guardian-token";
const authClearedListeners = new Set();
export function onAuthCleared(listener) { authClearedListeners.add(listener); return () => authClearedListeners.delete(listener); }
// The token remains inside this temporary request closure. It is never placed
// in a call record, public state, error or diagnostic output.
export function captureAuthRequest() {
  const token = typeof sessionStorage === 'undefined' ? '' : sessionStorage.getItem(TOKEN);
  return token ? (url, options = {}) => fetch(url, { ...options, headers: { ...options.headers, 'X-Wearable-Token': token } }) : undefined;
}
export function authHeaders() { return { "X-Wearable-Token": sessionStorage.getItem(TOKEN) || "" }; }
export function saveAuth(token, account) {
  if (!token) throw Error("登录响应缺少会话凭据");
  sessionStorage.setItem(TOKEN, token); sessionStorage.setItem("rolling-session", account);
}
export function clearAuth() {
  const request = captureAuthRequest();
  sessionStorage.removeItem(TOKEN); sessionStorage.removeItem("rolling-session");
  for (const listener of authClearedListeners) {
    try { Promise.resolve(listener({ request })).catch(() => {}); } catch { /* Auth must clear even if local cleanup fails. */ }
  }
}
export async function authFetch(url, options = {}) {
  const headers = { ...options.headers, ...authHeaders() };
  const token = headers["X-Wearable-Token"];
  const response = await fetch(url, { ...options, headers });
  // An expired request can finish after a different account has logged in.
  // Only the session that sent this request may be invalidated by its response.
  if (response.status === 401 && token && token === authHeaders()["X-Wearable-Token"]) {
    clearAuth(); window.location.hash = "/login";
  }
  return response;
}
