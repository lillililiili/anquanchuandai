<script setup>
import AppButton from "@/components/ui/AppButton.vue";
import { closeModal } from "@/stores/modal";
import { toast } from "@/stores/notify";
import { downloadMedia } from "./media";

const props = defineProps({
  mediaId: { type: String, default: "" },
});

async function save() {
  try {
    await downloadMedia(props.mediaId);
  } catch (error) {
    toast(error.message || "操作失败", true);
  }
}
</script>

<template>
  <AppButton tone="primary" icon="download-line" @click="save">下载资料</AppButton>
  <AppButton @click="closeModal">关闭</AppButton>
</template>
