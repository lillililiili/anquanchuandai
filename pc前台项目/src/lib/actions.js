import { assetForArea } from "@/mock/data";
import { db } from "@/mock/runtime";
import { session } from "@/stores/session";
import { toast } from "@/stores/notify";
import { blobPut, imageBlob } from "./files";

export function go(route) {
  location.hash = "#/" + String(route).replace(/^#?\//, "");
}

export async function capturePhoto(personId) {
  const device = db.currentDevices(personId).find((item) => item.type === "H");
  if (!device || device.video !== "available") throw Error("视频通道不可用，暂时无法抓拍");
  const asset = assetForArea(db.person(personId)?.area);
  const blob = await imageBlob(asset);
  const blobId = "capture-" + crypto.randomUUID();
  await blobPut(blobId, blob);
  session.media = db.capture(personId, "photo", 0, { blobId });
  toast("抓拍已保存，可在现场资料中查看");
}

export function toggleRecording(personId) {
  const device = db.currentDevices(personId).find((item) => item.type === "H");
  if (!session.recording && (!device || device.video !== "available")) {
    throw Error("视频通道不可用，暂时无法录像");
  }
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

export function callPerson(personId) {
  const person = db.person(personId);
  if (!person || !person.active) throw Error("人员不可用");
  const existing = db.state.calls.find((call) => call.status !== "已结束");
  if (existing) {
    session.selectedMembers = [...existing.members];
    go("dispatch");
    toast("已打开当前通话，可邀请该人员加入");
    return;
  }
  db.startCall([personId], "单呼", person.station);
  session.selectedMembers = [personId];
  go("dispatch");
}

export async function runGuarded(fn) {
  try {
    await fn();
  } catch (error) {
    toast(error.message || "操作失败", true);
  }
}
