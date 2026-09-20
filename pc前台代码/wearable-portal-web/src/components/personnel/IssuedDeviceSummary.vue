<script setup>
import { deviceTypes, labels } from '@/utils/portal-contract'
defineProps({ equipment: { type: Object, required: true } })
</script>
<template>
  <span v-if="equipment.state !== 'AVAILABLE'" class="issued-unavailable">领用设备：{{ labels[equipment.state] || '待确认' }}</span>
  <span v-else class="issued-device-summary">
    <span v-for="(label, key) in deviceTypes" :key="key" class="issued-device" :data-state="equipment.data[key].assignmentState">
      <span class="issued-device-label">{{ label }} · {{ equipment.data[key].assignmentState === 'UNKNOWN' ? '领用待确认' : labels[equipment.data[key].assignmentState] }}</span>
      <span v-if="equipment.data[key].assignmentState === 'ASSIGNED'" class="issued-device-code">{{ equipment.data[key].devices.map(d => d.deviceCode).join('、') }}</span>
    </span>
  </span>
</template>
<style scoped>
.issued-device-summary { display: grid; gap: 5px; width: 100%; min-width: 0; }
.issued-device { display: flex; flex-wrap: wrap; align-items: baseline; gap: 3px 9px; padding: 5px 8px; border: 1px solid #42637b; border-radius: 5px; background: #12334b; font-size: 12px; }
.issued-device[data-state="ASSIGNED"] { border-color: #327b87; background: #134351; }
.issued-device-label { white-space: nowrap; color: #dbf3ff; }
.issued-device[data-state="ASSIGNED"] .issued-device-label { color: #8ff3d5; }
.issued-device[data-state="CONFLICT"] .issued-device-label { color: #ffd08a; }
.issued-device-code { color: #c2d9e8; overflow-wrap: anywhere; min-width: 0; }
.issued-unavailable { font-size: 12px; color: #bed4e6; }
</style>
