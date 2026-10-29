import { ref } from "vue";
import { createStore } from "./data.js";
import { authFetch, authHeaders, clearAuth } from "../lib/auth.js";
import { createEventApi } from "../lib/guardian-events.js";
import { createLocationApi } from "../lib/guardian-location.js";
import { DEMO_MODE } from "../lib/data-mode.js";
import { createBusinessCommands } from '../lib/business-commands.js';

export const tick = ref(0);
export const connection = ref({ status: "connecting", message: "正在连接后端，暂不能办理业务" });
const storage = typeof localStorage === "undefined" ? null : localStorage;
export const db = createStore(storage, { demoMode: DEMO_MODE, requiredDataVersion: 'wearable-person-v2' });
let writes = 0;
let pulling = false;
function unavailable(message = "后端未连接，当前显示缓存台账；实时状态以有效上报为准，恢复连接后自动刷新，暂不能办理业务") {
  connection.value = { status: "offline", message };
}
function readable(state) { return /[\u4e00-\u9fff]/.test(state?.stations?.[0]?.name || ""); }

// Install the remote commit even when the first connection fails.
db.setRemoteCommit(() => {
  throw Error('请通过对应业务操作保存，整份业务快照不可写入');
});
const businessCommand = createBusinessCommands({ current: () => db.state, replace: state => db.replaceRemote(state), request: (path, body) => {
  if (connection.value.status !== "online") throw Error("后端未连接，修改未保存；请等待恢复连接");
  writes++;
  try {
    const xhr = new XMLHttpRequest();
    xhr.open("POST", path, false);
    xhr.setRequestHeader("Content-Type", "application/json; charset=utf-8");
    for (const [key, value] of Object.entries(authHeaders())) xhr.setRequestHeader(key, value);
    try { xhr.send(JSON.stringify(body)); }
    catch { unavailable(); throw Error("后端未连接，修改未保存"); }
    if (xhr.status === 401) { clearAuth(); unavailable("登录已失效，请重新登录"); window.location.hash = "/login"; }
    if (xhr.status === 0 || xhr.status >= 500) unavailable();
    if (xhr.status === 0 || xhr.status >= 400) {
      let message = "后端未连接，修改未保存";
      try { message = JSON.parse(xhr.responseText).message || message; } catch { /* transport error */ }
      throw Object.assign(Error(message), { code: xhr.status });
    }
    return JSON.parse(xhr.responseText || '{}');
  } finally { writes--; }
} });
if (!DEMO_MODE) {
  db.saveFence = (id, fields) => businessCommand('fences.save', { id: id || null, fields }).id;
  db.toggleFence = (id, enabled) => businessCommand('fences.toggle', { id, enabled });
  db.deleteFence = id => businessCommand('fences.archive', { id });
  db.saveGroup = (id, name, members, station) => businessCommand('groups.save', { id: id || null, name, members, station }).id;
  db.movePerson = () => { throw Error('真实位置仅由设备上报'); };
}
db.subscribe(() => { tick.value++; });

export async function refreshSnapshot() {
  if (!storage || writes || pulling) return false;
  if (!authHeaders()["X-Wearable-Token"]) { unavailable("请先登录后连接业务数据"); return false; }
  pulling = true;
  const before = db.revision();
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 15000);
  try {
    const response = await authFetch("/api/guardian/v1/snapshot", { signal: controller.signal });
    if (!response.ok) throw Error("后端读取失败");
    const body = await response.json();
    if (!readable(body.state)) throw Error("后端数据格式错误");
    if (writes || db.revision() !== before) return false;
    db.replaceRemote(body.state);
    connection.value = { status: "online", message: "" };
    await refreshCallStatuses(controller.signal);
    return true;
  } catch { unavailable(); return false; }
  finally { clearTimeout(timer); pulling = false; }
}

export const guardianReady = refreshSnapshot();
export const locationApi = createLocationApi(authFetch);
async function refreshCallStatuses(signal) {
  const active = db.state.calls.filter(call => call.rtc?.callId && call.status !== '已结束');
  await Promise.allSettled(active.map(async call => {
    const response = await authFetch(`/api/guardian/v1/helmet/calls/${encodeURIComponent(call.rtc.callId)}`,{signal});
    if (!response.ok) { db.applyServerCallStatus(call.id, { status:'unknown' }); return; }
    const result = await response.json();
    db.applyServerCallStatus(call.id, result);
    if (['ended','failed'].includes(result.status)) { const rtc = await import('../lib/rtc.js'); if(rtc.getActiveCallId()===call.rtc.callId)await rtc.leaveChannel(); }
  }));
}
const eventApi = createEventApi({ fetchImpl: authFetch, refresh: async () => { while (pulling) await new Promise(resolve => setTimeout(resolve, 25)); return refreshSnapshot(); }, current: id => db.event(id) });
db.claim = id => eventApi.command(id, "claim");
db.verify = (id, form, submit) => eventApi.command(id, submit ? "verification" : "verification-draft", form);
db.addEventPhoto = (id, blobId, name, expectedVersion) => eventApi.command(id, "photos", { blobId, name, expectedVersion });
db.observe = (id, form) => eventApi.command(id, "observations", form);
db.sos = (action, eventId) => eventApi.command(eventId, action === "join" ? "assist-join" : "assist-end");
if (typeof window !== "undefined") {
  window.setInterval(refreshSnapshot, 5000);
  window.addEventListener("online", refreshSnapshot);
}
if (typeof XMLHttpRequest !== "undefined") db.setVoice(guardianVoice);

function guardianVoice(path, body) {
  if (connection.value.status !== "online") throw Error("后端未连接，不能发起通信");
  const xhr = new XMLHttpRequest();
  xhr.open("POST", path, false);
  xhr.setRequestHeader("Content-Type", "application/json; charset=utf-8");
  for (const [key, value] of Object.entries(authHeaders())) xhr.setRequestHeader(key, value);
  try { xhr.send(JSON.stringify(body)); } catch { throw Error("请求安全帽异常"); }
  if (xhr.status === 401) { clearAuth(); window.location.hash = "/login"; throw Error("登录已失效，请重新登录"); }
  if (xhr.status === 0 || xhr.status >= 500) throw Error("请求安全帽异常");
  if (xhr.status >= 400) {
    let message = "请求安全帽异常";
    try { message = JSON.parse(xhr.responseText).message || message; } catch { /* use default */ }
    throw Error(message);
  }
  return JSON.parse(xhr.responseText || "{}");
}
