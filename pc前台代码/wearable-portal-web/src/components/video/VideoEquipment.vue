<script setup>
import { computed } from 'vue'
import DataState from '@/components/personnel/DataState.vue'
import { videoLabels } from '@/utils/video-contract'
defineProps({ section: { type: Object, default: null } })
const types = computed(() => ['HELMET', 'BELT', 'WATCH'])
</script>
<template><section class="video-related"><h3>穿戴装备摘要</h3><DataState v-if="section?.state !== 'AVAILABLE'" :state="section?.state" :reason="section?.reasonCode" compact /><div class="video-equipment"><div v-for="type in types" :key="type"><strong>{{ videoLabels[type] }}</strong><template v-if="section?.state === 'AVAILABLE' && section.data.some(d => d.type === type)"><span v-for="item in section.data.filter(d => d.type === type)" :key="item.id">{{ item.name }}</span><small>关联有证据；不代表历史领用流水</small></template><small v-else>关联未知</small><small v-if="type !== 'HELMET'">厂家能力待确认</small></div></div></section></template>
