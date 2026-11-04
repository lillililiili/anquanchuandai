<script setup>
import { computed } from 'vue';
import { deviceLocalRecordingPresentation } from '../../../../shared/device-local-recording.mjs';
import { formatBeijingDateTime } from '@/lib/date-time';
const props = defineProps({ device: { type: Object, default: null } });
const record = computed(() => deviceLocalRecordingPresentation(props.device));
const receivedTime = computed(() => formatBeijingDateTime(record.value.receivedAt));
</script>

<template>
  <div v-if="record.visible" class="device-local-recording">
    <div class="local-recording-heading"><span>{{ record.title }}</span><strong>{{ record.label }}</strong></div>
    <small v-if="record.reported">平台接收时间：{{ receivedTime === '—' ? '时间未确认' : receivedTime + '（北京时间）' }}</small>
    <small v-if="record.reported">上报时人员：{{ record.personLabel }}</small>
    <p>{{ record.note }}</p>
  </div>
</template>

<style scoped>
.device-local-recording { min-width: 0; }
.local-recording-heading { display: flex; flex-wrap: wrap; gap: 6px 12px; align-items: baseline; line-height: 1.5; }
.local-recording-heading > span { color: var(--theme-muted); font-size: 12px; }
.local-recording-heading > strong { font-weight: 500; white-space: nowrap; }
.device-local-recording > small { display: block; margin-top: 5px; line-height: 1.5; overflow-wrap: anywhere; }
.device-local-recording > p { color: var(--theme-muted); font-size: 12px; line-height: 1.5; margin: 6px 0 0; }
</style>
