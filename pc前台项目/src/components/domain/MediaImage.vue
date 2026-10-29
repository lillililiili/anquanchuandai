<script setup>
import { onUnmounted, ref, watch } from "vue";
import { blobGet } from "@/lib/files";
import { mediaUrl } from '@/lib/helmet-media';
import { db } from '@/mock/runtime';

const props = defineProps({
  media: { type: Object, default: null },
});

const src = ref("");
const alt = ref("");
let objectUrl = "";
let generation = 0;

async function load() {
  const operation = ++generation;
  src.value = '';
  if (objectUrl) URL.revokeObjectURL(objectUrl);
  objectUrl = "";
  const media = props.media;
  if (!media) {
    src.value = "";
    alt.value = "";
    return;
  }
  alt.value = media.title || "";
  if(media.url){src.value=mediaUrl(media.url)||'';alt.value=src.value?alt.value:'原始文件地址无效';return;}
  if (!media.blobId) {
    src.value = db.demoMode ? "/assets/" + (media.asset || "scene-boiler.png") : '';
    if (!db.demoMode) alt.value = '暂无可验证的原始文件，台账记录保留';
    return;
  }
  try {
    const blob = await blobGet(media.blobId);
    if(operation!==generation)return;
    if (!blob) {
      src.value = "";
      alt.value = "本地照片文件不存在";
      return;
    }
    objectUrl = URL.createObjectURL(blob);
    src.value = objectUrl;
  } catch (error) {
    if(operation!==generation)return;
    src.value = "";
    alt.value = error.message;
  }
}

watch(() => props.media, load, { immediate: true, deep: true });
onUnmounted(() => {
  generation++;
  if (objectUrl) URL.revokeObjectURL(objectUrl);
});
</script>

<template>
  <video v-if="src && media?.url && String(media.kind).toLowerCase()==='video'" :src="src" :aria-label="alt || '设备录像'" muted playsinline preload="metadata" />
  <img v-else-if="src" :src="src" :alt="alt" />
  <div v-else class="empty-state" role="status">{{ alt || '暂无影像文件' }}</div>
</template>
