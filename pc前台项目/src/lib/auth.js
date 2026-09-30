const TOKEN = "wearable-guardian-token";
export function authHeaders() { return { "X-Wearable-Token": sessionStorage.getItem(TOKEN) || "" }; }
export function saveAuth(token, account) {
  if (!token) throw Error("登录响应缺少会话凭据");
  sessionStorage.setItem(TOKEN, token); sessionStorage.setItem("rolling-session", account);
}
export function clearAuth() { sessionStorage.removeItem(TOKEN); sessionStorage.removeItem("rolling-session"); }
export async function authFetch(url, options = {}) {
  const response = await fetch(url, { ...options, headers: { ...options.headers, ...authHeaders() } });
  if (response.status === 401) { clearAuth(); window.location.hash = "/login"; }
  return response;
}
