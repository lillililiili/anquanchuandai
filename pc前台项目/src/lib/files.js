import { authFetch } from "./auth.js";
function fileUrl(id) {
  return "/api/guardian/v1/files/" + encodeURIComponent(id);
}

async function failureMessage(response, fallback) {
  try {
    return (await response.json()).message || fallback;
  } catch {
    return fallback;
  }
}

export async function blobPut(id, blob) {
  let response;
  try {
    response = await authFetch(fileUrl(id), {
      method: "PUT",
      headers: { "Content-Type": blob.type || "application/octet-stream" },
      body: blob,
    });
  } catch {
    throw Error("照片保存失败，请检查磁盘空间");
  }
  if (!response.ok) {
    const fallback = response.status === 413 ? "图片不能超过 10MB" : "照片保存失败，请检查磁盘空间";
    throw Error(await failureMessage(response, fallback));
  }
  return id;
}

export async function blobGet(id) {
  let response;
  try {
    response = await authFetch(fileUrl(id));
  } catch {
    throw Error("照片读取失败");
  }
  if (response.status === 404) return undefined;
  if (!response.ok) throw Error(await failureMessage(response, "照片读取失败"));
  return response.blob();
}

export function download(filename, content, type = "text/plain;charset=utf-8") {
  const blob = content instanceof Blob ? content : new Blob([content], { type });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.append(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 60000);
}

export function csvContent(headers, rows) {
  const cell = (value) =>
    '"' +
    String(value ?? "")
      .replace(/^[=+@-]/, "'$&")
      .replace(/"/g, '""') +
    '"';
  return "\ufeff" + [headers, ...rows].map((row) => row.map(cell).join(",")).join("\r\n");
}

export async function imageBlob(asset) {
  const response = await fetch("/assets/" + asset);
  if (!response.ok) throw Error("无法读取现场图片");
  return response.blob();
}
