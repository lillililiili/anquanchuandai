<script setup>
import { onUnmounted, ref, watch } from 'vue';
import { loadSplitMedia } from '@/lib/split-media-file';
import { onAuthCleared } from '@/lib/auth';
const props = defineProps({ media: { type: Object, required: true } });
const url = ref(''), error = ref(''), loading = ref(false), kind = ref('');
let controller, generation = 0;
function clear() { ++generation; controller?.abort(); if (url.value) URL.revokeObjectURL(url.value); url.value = ''; }
async function load() {
  clear(); const current = generation; controller = new AbortController(); loading.value = true; error.value = '';
  try { const blob = await loadSplitMedia(props.media, { signal: controller.signal }); if (current !== generation) return; url.value = URL.createObjectURL(blob); kind.value = blob.type.split('/')[0]; }
  catch (failure) { if (current === generation && failure.name !== 'AbortError') error.value = failure.message; }
  finally { if (current === generation) loading.value = false; }
}
watch(() => [props.media.id, props.media.url], load, { immediate: true });
const unsubscribe = onAuthCleared(clear);
onUnmounted(() => { clear(); unsubscribe(); });
</script>
<template><div class="split-media-preview" :aria-busy="loading"><p v-if="loading" role="status">正在读取设备文件…</p><video v-if="url && kind === 'video'" :src="url" controls playsinline :aria-label="media.title || '分体帽录像'" /><audio v-else-if="url && kind === 'audio'" :src="url" controls /><img v-else-if="url" :src="url" :alt="media.title || '分体帽照片'" /><p v-if="error" role="alert">{{ error }} <button class="btn" @click="load">重试</button></p></div></template>
<style scoped>.split-media-preview video,.split-media-preview img{max-width:100%;max-height:65vh;object-fit:contain}.split-media-preview{min-height:120px;text-align:center}</style>
