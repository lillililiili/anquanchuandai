<script setup>
import { computed } from 'vue';
import { deviceControlsReference } from '../../../../shared/device-controls.mjs';
const props = defineProps({ device: { type: Object, default: null } });
const reference = computed(() => deviceControlsReference(props.device));
</script>

<template>
  <details v-if="reference" class="device-controls-reference">
    <summary>{{ reference.title }} <span>设备本地操作说明</span></summary>
    <p>{{ reference.description }}</p>
    <dl>
      <template v-for="control in reference.controls" :key="control.id">
        <dt>{{ control.key }} · {{ control.gesture }}</dt>
        <dd>{{ control.deviceEffect }}<small>{{ control.platformEffect }}</small></dd>
      </template>
    </dl>
    <p class="reference-source">资料依据：{{ reference.source.document }} · 第 {{ reference.source.page }} 页</p>
  </details>
</template>

<style scoped>
.device-controls-reference { min-width: 0; line-height: 1.5; }
summary { cursor: pointer; padding: 8px 0; }
summary:focus-visible { outline: 2px solid currentColor; outline-offset: 2px; }
summary > span, small, .reference-source { color: var(--theme-muted); font-size: 12px; }
summary > span { display: block; padding-left: 16px; }
p { margin: 8px 0; }
dl { margin: 12px 0; }
dt { font-weight: 600; margin-top: 12px; }
dd { margin: 4px 0 0; overflow-wrap: anywhere; }
small { display: block; margin-top: 4px; }
</style>
