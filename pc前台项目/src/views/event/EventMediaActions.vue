<script setup>
import AppButton from "@/components/ui/AppButton.vue";
import { db } from "@/mock/runtime";
import { closeModal } from "@/stores/modal";
import { toast } from "@/stores/notify";
import { blobGet, download, imageBlob } from "@/lib/files";

const props = defineProps({
  media: { type: Object, required: true },
});

let busy = false;

async function save() {
  if (busy) return;
  busy = true;
  try {
    const media = db.state.media.find((item) => item.id === props.media.id);
    if (!media) throw Error("资料不存在");
    if (media.kind === "video") {
      download(
        media.id + "-模拟录像记录.json",
        JSON.stringify(
          {
            说明: "图片模拟录像记录，不是真实视频文件",
            资料编号: media.id,
            人员: media.snapshot.personName,
            设备: media.deviceId,
            作业: media.snapshot.workName,
            拍摄时间: media.created,
            时长秒: media.duration,
          },
          null,
          2,
        ),
        "application/json;charset=utf-8",
      );
      const blob = media.blobId ? await blobGet(media.blobId) : await imageBlob(media.asset);
      if (blob) download(media.id + "-封面." + (blob.type === "image/webp" ? "webp" : "png"), blob);
    } else {
      const blob = media.blobId ? await blobGet(media.blobId) : await imageBlob(media.asset);
      if (!blob) throw Error("本地照片文件不存在");
      const extension = blob.type === "image/jpeg" ? "jpg" : blob.type === "image/webp" ? "webp" : "png";
      download(media.id + "." + extension, blob);
    }
    toast("资料已下载");
  } catch (error) {
    toast(error.message || "操作失败", true);
  } finally {
    busy = false;
  }
}
</script>

<template>
  <AppButton tone="primary" icon="download-line" @click="save">下载资料</AppButton>
  <AppButton @click="closeModal">关闭</AppButton>
</template>
