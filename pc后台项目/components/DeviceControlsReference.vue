<script setup>
import { computed } from 'vue'
import { deviceControlsReference } from '../../shared/device-controls.mjs'
const props = defineProps({ device: { type: Object, default: null } })
const reference = computed(() => deviceControlsReference(props.device))
</script>
<template>
  <details v-if="reference" class="device-controls-reference">
    <summary>{{ reference.title }} · 设备本地操作说明</summary>
    <p>{{ reference.description }}</p>
    <dl><template v-for="control in reference.controls" :key="control.id"><dt>{{ control.key }} · {{ control.gesture }}</dt><dd>{{ control.deviceEffect }}<small>{{ control.platformEffect }}</small></dd></template></dl>
    <p class="muted">资料依据：{{ reference.source.document }} · 第 {{ reference.source.page }} 页</p>
  </details>
</template>
<style scoped>
.device-controls-reference { min-width:0; line-height:1.5; margin:16px 0; padding:12px 16px; border:1px solid var(--line); border-radius:4px; }
summary { cursor:pointer; padding:6px 0; }
summary:focus-visible { outline:2px solid currentColor; outline-offset:2px; }
dt { margin-top:12px; font-weight:600; }
dd { margin:4px 0 0; overflow-wrap:anywhere; }
small { display:block; color:var(--muted); margin-top:4px; }
</style>
