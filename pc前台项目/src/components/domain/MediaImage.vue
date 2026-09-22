<script setup>
import { onUnmounted, ref, watch } from "vue";
import { blobGet } from "@/lib/files";

const props = defineProps({
  media: { type: Object, default: null },
});

const src = ref("");
const alt = ref("");
let objectUrl = "";

async function load() {
  if (objectUrl) URL.revokeObjectURL(objectUrl);
  objectUrl = "";
  const media = props.media;
  if (!media) {
    src.value = "";
    alt.value = "";
    return;
  }
  alt.value = media.title || "";
  if (!media.blobId) {
    src.value = "/assets/" + (media.asset || "scene-boiler.png");
    return;
  }
  try {
    const blob = await blobGet(media.blobId);
    if (!blob) {
      src.value = "";
      alt.value = "本地照片文件不存在";
      return;
    }
    objectUrl = URL.createObjectURL(blob);
    src.value = objectUrl;
  } catch (error) {
    src.value = "";
    alt.value = error.message;
  }
}

watch(() => props.media, load, { immediate: true, deep: true });
onUnmounted(() => {
  if (objectUrl) URL.revokeObjectURL(objectUrl);
});
</script>

<template>
  <img :src="src" :alt="alt" />
</template>
