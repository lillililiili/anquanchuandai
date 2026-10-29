import { db } from "@/mock/runtime";
import { toast } from "@/stores/notify";
import { blobGet, download, imageBlob } from "@/lib/files";
import { mediaUrl } from '@/lib/helmet-media';

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
  if (!db.demoMode || !media.asset) return null;
  try {
    return await imageBlob(media.asset);
  } catch {
    return null;
  }
}

export async function downloadMedia(id) {
  const media = typeof id === 'object' ? id : db.state.media.find((item) => item.id === id);
  if (!media) {
    toast("资料不存在", true);
    return;
  }
  if (media.url) {
    const url=mediaUrl(media.url);
    if(!url)throw Error('原始文件地址无效');
    if(media.expiresAt && Date.parse(media.expiresAt)<=Date.now())throw Error('文件授权已过期，请刷新设备资料');
    const link=document.createElement('a');link.href=url;link.download=media.name||media.id;link.target='_blank';link.rel='noopener noreferrer';link.click();
    toast('已打开设备原始文件，可在浏览器中保存');return;
  }
  const blob = await fileBlob(media);
  if (!db.demoMode && (media.kind === 'video' || !blob)) throw Error('暂无可下载的原始文件，台账记录仍保留');
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
