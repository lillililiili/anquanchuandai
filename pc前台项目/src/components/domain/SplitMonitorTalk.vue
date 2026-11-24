<script setup>
import { onBeforeUnmount, ref } from 'vue';
import AppButton from '@/components/ui/AppButton.vue';
import { createMonitorIntercom } from '@/lib/monitor-intercom';

const props = defineProps({ live: { type: Object, required: true } });
const emit = defineEmits(['listen']);
const phase = ref('off'), error = ref('');
const control = createMonitorIntercom({ onChange(value, message) { phase.value = value; error.value = message; } });
const labels = { off: '开启对讲', preparing: '取消麦克风授权', connecting: '取消对讲连接', on: '关闭麦克风', closing: '正在关闭麦克风' };
function toggle() {
  if (phase.value !== 'off') return control.stop();
  emit('listen');
  return control.start(props.live);
}
onBeforeUnmount(() => { void control.stop(); });
</script>
<template>
  <div class="monitor-microphone">
    <span v-if="phase === 'connecting'" role="status">正在连接对讲…</span>
    <span v-if="phase === 'on'" role="status">麦克风已开启</span>
    <span v-if="error" role="alert">{{ error }}</span>
    <AppButton icon="mic-line" :aria-pressed="phase === 'on'" :disabled="phase === 'closing'" @click.stop="toggle">{{ labels[phase] }}</AppButton>
  </div>
</template>
<style scoped>
.monitor-microphone{display:flex;align-items:center;justify-content:flex-end;flex-wrap:wrap;gap:8px;padding:6px 10px;color:var(--theme-text);background:var(--theme-card)}
.monitor-microphone :deep(button){min-height:44px}
</style>
