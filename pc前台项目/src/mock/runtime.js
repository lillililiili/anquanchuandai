import { ref } from "vue";
import { KEY, createStore } from "./data.js";

export const tick = ref(0);
export let db = null;

const storage = typeof localStorage === "undefined" ? null : localStorage;

function readable(state) {
  return /[\u4e00-\u9fff]/.test(state?.stations?.[0]?.name || "");
}

async function pullSnapshot() {
  if (!storage) return false;
  try {
    const response = await fetch("/api/guardian/v1/snapshot");
    if (!response.ok) return false;
    const body = await response.json();
    if (!readable(body.state)) return false;
    storage.setItem(KEY, JSON.stringify(body.state));
    return true;
  } catch {
    return false;
  }
}

let writes = 0;

function watchBackend() {
  db.setRemoteCommit((next) => {
    writes += 1;
    try {
      const xhr = new XMLHttpRequest();
      xhr.open("PUT", "/api/guardian/v1/snapshot", false);
      xhr.setRequestHeader("Content-Type", "application/json; charset=utf-8");
      try {
        xhr.send(JSON.stringify(next));
      } catch {
        throw Error("后端未连接，修改未保存");
      }
      if (xhr.status === 0) throw Error("后端未连接，修改未保存");
      if (xhr.status >= 400) {
        let message = xhr.status >= 500 ? "后端未连接，修改未保存" : "保存失败";
        try {
          message = JSON.parse(xhr.responseText).message || message;
        } catch {
          /* 没有 JSON 正文时保留上面的默认文案。 */
        }
        throw Error(message);
      }
    } finally {
      writes -= 1;
    }
  });
  window.setInterval(refreshSnapshot, 5000);
}

async function refreshSnapshot() {
  if (!db || writes) return;
  const before = db.revision();
  let response;
  try {
    response = await fetch("/api/guardian/v1/snapshot");
  } catch {
    return;
  }
  if (writes || !response.ok || db.revision() !== before) return;
  let body;
  try {
    body = await response.json();
  } catch {
    return;
  }
  if (writes || db.revision() !== before || !readable(body.state)) return;
  const seq = body.state.seq || 0;
  if (seq < before) return;
  if (seq === before && JSON.stringify(body.state) === JSON.stringify(db.state)) return;
  db.replaceRemote(body.state);
}

export const guardianReady = (async () => {
  const online = await pullSnapshot();
  db = createStore(storage);
  db.subscribe(() => {
    tick.value += 1;
  });
  if (online) watchBackend();
  if (typeof XMLHttpRequest !== "undefined") db.setVoice(guardianVoice);
})();

function guardianVoice(path, body) {
  const xhr = new XMLHttpRequest();
  xhr.open("POST", path, false);
  xhr.setRequestHeader("Content-Type", "application/json; charset=utf-8");
  try {
    xhr.send(JSON.stringify(body));
  } catch {
    throw Error("请求安全帽异常");
  }
  if (xhr.status === 0 || xhr.status >= 500) throw Error("请求安全帽异常");
  if (xhr.status >= 400) {
    let message = "请求安全帽异常";
    try {
      message = JSON.parse(xhr.responseText).message || message;
    } catch {
      /* 没有 JSON 正文时使用统一的安全帽失败提示。 */
    }
    throw Error(message);
  }
  return JSON.parse(xhr.responseText || "{}");
}
