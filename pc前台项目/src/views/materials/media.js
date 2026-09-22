import { db } from "@/mock/runtime";
import { toast } from "@/stores/notify";
import { blobGet, download, imageBlob } from "@/lib/files";

export function durationText(value) {
  const total = Number(value) || 0;
  return String(Math.floor(total / 60)).padStart(2, "0") + ":" + String(total % 60).padStart(2, "0");
}

function recordBody(media) {
  return JSON.stringify(
    {
      说明: "图片模拟录像记录，不是真实视频文件",
      资料编号: media.id,
      人员: media.snapshot?.personName,
      设备: media.deviceId,
      作业: media.snapshot?.workName,
      拍摄时间: media.created,
      时长秒: media.duration,
    },
    null,
    2,
  );
}

async function fileBlob(media) {
  if (media.blobId) {
    try {
      const stored = await blobGet(media.blobId);
      if (stored) return stored;
    } catch {
      /* 读取失败时继续尝试资源文件。 */
    }
  }
  if (!media.asset) return null;
  try {
    return await imageBlob(media.asset);
  } catch {
    return null;
  }
}

export async function downloadMedia(id) {
  const media = db.state.media.find((item) => item.id === id);
  if (!media) {
    toast("资料不存在", true);
    return;
  }
  const blob = await fileBlob(media);
  if (media.kind === "video") {
    download(media.id + "-模拟录像记录.json", recordBody(media), "application/json;charset=utf-8");
    if (blob) download(media.id + "-封面." + (blob.type === "image/webp" ? "webp" : "png"), blob);
  } else if (blob) {
    const extension = blob.type === "image/jpeg" ? "jpg" : blob.type === "image/webp" ? "webp" : "png";
    download(media.id + "." + extension, blob);
  } else {
    download(media.id + "-模拟录像记录.json", recordBody(media), "application/json;charset=utf-8");
  }
  toast("资料已下载");
}
