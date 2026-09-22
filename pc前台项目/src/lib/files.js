let database;

function blobDB() {
  database ||= new Promise((resolve, reject) => {
    const request = indexedDB.open("rolling-native-files", 1);
    request.onupgradeneeded = () => request.result.createObjectStore("files");
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(Error("无法访问本地文件存储"));
  });
  return database;
}

export async function blobPut(id, blob) {
  const store = await blobDB();
  return new Promise((resolve, reject) => {
    const transaction = store.transaction("files", "readwrite");
    transaction.objectStore("files").put(blob, id);
    transaction.oncomplete = () => resolve(id);
    transaction.onerror = () => reject(Error("照片保存失败，请检查磁盘空间"));
    transaction.onabort = () => reject(Error("照片保存事务已取消"));
  });
}

export async function blobGet(id) {
  const store = await blobDB();
  return new Promise((resolve, reject) => {
    const request = store.transaction("files").objectStore("files").get(id);
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(Error("照片读取失败"));
  });
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
