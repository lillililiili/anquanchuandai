import { assetForPerson } from "@/mock/data";
import { db } from "@/mock/runtime";
import { session } from "@/stores/session";
import { toast } from "@/stores/notify";
import { blobPut, imageBlob } from "./files";
import { isRealDevice } from './device-telemetry';
import { createHelmetMediaApi } from './helmet-media';
import { authFetch } from './auth';
import { personFeature, operationContext } from './person-equipment';
import { createMediaOperations } from './media-operations';
const mediaOperations = createMediaOperations({ api: createHelmetMediaApi(authFetch), state: session });
export const refreshRecording = () => mediaOperations.refresh();

export function go(route) {
  location.hash = "#/" + String(route).replace(/^#?\//, "");
}

export async function capturePhoto(personId) {
  const device = db.currentDevices(personId).find((item) => item.type === "H");
  if (isRealDevice(device)) {
    const feature = personFeature(db, personId, 'photo');
    if (!feature.available) throw Error(feature.reason);
    const result = await mediaOperations.photo(operationContext(feature));
    toast(result.status === 'completed' ? '照片已返回，可在现场资料中查看' : ['unknown','requesting'].includes(result.status) ? '拍照结果待确认，可在现场资料查看回执' : '拍照请求已提交，照片返回后在现场资料中查看');
    return;
  }
  if (!db.demoMode) throw Error('暂无真实设备视频，不能生成示例抓拍');
  if (!device || device.video !== "available") throw Error("视频通道不可用，暂时无法抓拍");
  const asset = assetForPerson(personId);
  const blob = await imageBlob(asset);
  const blobId = "capture-" + crypto.randomUUID();
  await blobPut(blobId, blob);
  session.media = db.capture(personId, "photo", 0, { blobId });
  toast("抓拍已保存，可在现场资料中查看");
}

export async function toggleRecording(personId) {
  if (session.recording?.real && session.recording.person === personId) return stopRecording();
  const device = db.currentDevices(personId).find((item) => item.type === "H");
  if (isRealDevice(device)) {
    if (session.recording) throw Error('请先结束正在进行的录像请求');
    const feature = personFeature(db, personId, 'recording');
    if (!feature.available) throw Error(feature.reason);
    const context = operationContext(feature);
    const result = await mediaOperations.start(context);
    toast(result.status === 'recording' ? '正在录制现场视频' : '录像请求已提交，等待实际视频与录制回执');return;
  }
  if (!db.demoMode) throw Error('暂无真实设备视频，不能生成示例录像');
  if (!session.recording && (!device || device.video !== "available")) {
    throw Error("视频通道不可用，暂时无法录像");
  }
  if (session.recording?.real) throw Error('请在对应真实安全帽页面停止录像');
  if (session.recording) {
    const current = session.recording;
    session.media = db.capture(current.person, "video", Math.max(1, Math.floor((Date.now() - current.start) / 1000)));
    session.recording = null;
    toast("模拟录像记录已保存（封面及录制时长）");
    return;
  }
  session.recording = { person: personId, start: Date.now() };
  toast("已开始模拟录像，点击停止保存记录");
}

export async function stopRecording() {
  const result = await mediaOperations.stop();
  if (!result) return;
  toast(result.status === 'completed' ? '录像请求已结束，请在现场资料查看结果' : result.status === 'finalizing' ? '录像正在封装，文件生成后可在现场资料查看' : '结束请求已提交，等待实际停止回执');
}

export async function callPerson(personId) {
  const person = db.person(personId);
  if (!person || !person.active) throw Error("人员不可用");
  session.selectedMembers = [personId];
  go('dispatch?personId=' + encodeURIComponent(personId));
}

export async function runGuarded(fn) {
  try {
    await fn();
  } catch (error) {
    toast(error.message || "操作失败", true);
  }
}
