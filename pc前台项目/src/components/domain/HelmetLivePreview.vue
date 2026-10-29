<script setup>
import { computed, onUnmounted, ref, watch } from 'vue';
import AppButton from '@/components/ui/AppButton.vue';
import LiveVideo from './LiveVideo.vue';
import { db, tick, connection } from '@/mock/runtime';
import { personFeature, operationContext } from '@/lib/person-equipment';
import { liveViewing } from '@/lib/live-session';
const props = defineProps({ personId: { type: String, required: true } });
const feature = computed(() => { tick.value; return personFeature(db, props.personId, 'video'); });
const available = computed(() => feature.value.available && connection.value.status === 'online');
const state = ref({ phase: 'idle', live: null, error: '' }), opened = ref(false);
let handle;
watch(() => JSON.stringify([props.personId, feature.value.deviceId, feature.value.assignmentId, feature.value.assignmentVersion, available.value]), () => {
  handle?.dispose(); handle = null; opened.value = false; state.value = { phase: 'idle', live: null, error: '' };
  if (available.value) handle = liveViewing.watch(operationContext(feature.value), value => { state.value = value; });
}, { immediate: true });
onUnmounted(() => handle?.dispose());
async function open() { if (!handle || !available.value) return; opened.value = true; await handle.open(); }
function close() { opened.value = false; handle?.close(); }
</script>
<template>
  <div class="helmet-preview" :aria-busy="opened && ['starting','waiting'].includes(state.phase)" @click.stop>
    <LiveVideo v-if="opened && state.live && available" :live="state.live" :label="`${db.person(personId)?.name || ''}的安全帽实时视频`" />
    <div v-else class="preview-start">
      <p>{{ !available ? (connection.status !== 'online' ? '业务连接中断，实时观看不可用' : feature.reason) : opened ? state.phase === 'starting' ? '正在请求开启直播…' : state.phase === 'waiting' ? '正在等待设备视频回传…' : '实时视频暂不可用' : '安全帽现场视频' }}</p>
      <AppButton v-if="!opened || state.phase === 'error'" :disabled="!available" @click="open">{{ opened ? '重试观看' : '查看实时视频' }}</AppButton>
      <p v-if="opened && state.error" role="alert">{{ state.error }}</p>
    </div>
    <AppButton v-if="opened" class="preview-stop" tone="small" @click="close">停止观看</AppButton>
  </div>
</template>
<style scoped>.helmet-preview{position:relative;height:100%;min-height:240px;background:#101621}.preview-start{display:flex;min-height:240px;padding:20px 20px 54px;box-sizing:border-box;flex-direction:column;align-items:center;justify-content:center;gap:12px;text-align:center}.preview-start p{margin:0}.helmet-preview :deep(.live-video){height:100%}.preview-stop{position:absolute;right:12px;top:12px;z-index:2}</style>
