<script setup>
import AppButton from "@/components/ui/AppButton.vue";
import { db } from "@/mock/runtime";
import { closeModal } from "@/stores/modal";
import { toast } from "@/stores/notify";
import { downloadMedia } from '../materials/media';

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
    await downloadMedia(media);
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
