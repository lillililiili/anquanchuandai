<script setup>
import { computed, onUnmounted, ref, watch } from "vue";
import { blobGet } from "@/lib/files";
import { mediaUrl } from '@/lib/helmet-media';
import { mediaPreviewKey } from '@/lib/media-preview-source';
import { db } from '@/mock/runtime';

const props = defineProps({
  media: { type: Object, default: null },
});

const src = ref("");
const alt = computed(() => props.media?.title || '');
const error = ref('');
const renderGeneration = ref(0);
const previewElement = ref(null);
let objectUrl = "";
let generation = 0;

async function load() {
  const operation = ++generation;
  renderGeneration.value = operation;
  src.value = '';
  error.value = '';
  if (objectUrl) URL.revokeObjectURL(objectUrl);
  objectUrl = "";
  const media = props.media;
  if (!media) {
    src.value = "";
    return;
  }
  if (media.url) {
    src.value = mediaUrl(media.url) || '';
    if (!src.value) error.value = '原始文件地址无效';
    return;
  }
  if (!media.blobId) {
    src.value = db.demoMode ? "/assets/" + (media.asset || "scene-boiler.png") : '';
    if (!db.demoMode) error.value = '暂无影像文件';
    return;
  }
  try {
    const blob = await blobGet(media.blobId);
    if(operation!==generation)return;
    if (!blob) {
      src.value = "";
      error.value = "本地照片文件不存在";
      return;
    }
    objectUrl = URL.createObjectURL(blob);
    src.value = objectUrl;
  } catch {
    if(operation!==generation)return;
    src.value = "";
    error.value = '预览加载失败，请重试';
  }
}

function onError(event) {
  // Ignore an error queued by a previous file after switching the preview.
  if (event?.target && event.target !== previewElement.value) return;
  src.value = '';
  error.value = '预览加载失败，请重试';
  if (objectUrl) URL.revokeObjectURL(objectUrl);
  objectUrl = '';
}

function retry() {
  // Polling keeps props up to date, including the latest server-issued ticket.
  return load();
}

watch([() => mediaPreviewKey(props.media), () => db.demoMode], load, { immediate: true });
onUnmounted(() => {
  generation++;
  if (objectUrl) URL.revokeObjectURL(objectUrl);
});
</script>

<template>
  <video v-if="src && media?.url && String(media.kind).toLowerCase()==='video'" :key="renderGeneration" ref="previewElement" :src="src" :aria-label="alt || '设备录像'" muted playsinline preload="metadata" @error="onError" />
  <img v-else-if="src" :key="renderGeneration" ref="previewElement" :src="src" :alt="alt" @error="onError" />
  <div v-else class="empty-state media-preview-empty" role="status">
    <span>{{ error || '暂无影像文件' }}</span>
    <button v-if="error && (media?.url || media?.blobId)" type="button" class="btn" @click.stop="retry" @keydown.stop>重试</button>
  </div>
</template>

<style scoped>
.media-preview-empty { display: flex; align-items: center; justify-content: center; gap: 12px; }
:global(.media-card .media-preview-empty ~ .play-overlay) { display: none; }
</style>
