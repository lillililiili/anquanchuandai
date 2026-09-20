<script setup>
import { computed } from 'vue'
import { eventTime } from '@/utils/event-contract'
const props = defineProps({ items: { type: Array, default: () => [] } })
defineEmits(['select'])
const start = computed(() => Math.min(...props.items.map(w => Date.parse(w.startsAt))))
const end = computed(() => Math.max(...props.items.map(w => Date.parse(w.endsAt))))
const bar = w => ({ marginLeft: ((Date.parse(w.startsAt) - start.value) / (end.value - start.value) * 100) + '%', width: ((Date.parse(w.endsAt) - Date.parse(w.startsAt)) / (end.value - start.value) * 100) + '%' })
</script>
<template><details v-if="items.length" class="work-time-window" aria-label="当前页来源计划时间窗"><summary>当前页来源计划时间窗 <span>展开查看</span></summary><p>{{ eventTime(new Date(start).toISOString()) }} ～ {{ eventTime(new Date(end).toISOString()) }}</p><p>仅来源计划，不代表实际工时；同一时段重叠不作安全判断。</p><div class="work-time-rows"><button v-for="w in items" :key="w.workId" :aria-label="w.name + '，计划 ' + eventTime(w.startsAt) + ' 至 ' + eventTime(w.endsAt)" @click="$emit('select', w.workId)"><span>{{ w.name }}</span><span class="work-time-track"><i :style="bar(w)" /></span></button></div></details></template>
<style scoped>
.work-time-window { border-top: 1px solid var(--border); padding-top: 18px; margin-top: 20px; }.work-time-window p { font-size: 12px; color: var(--text-secondary); }.work-time-rows { max-height: 200px; overflow: auto; padding: 8px 4px; }.work-time-rows button { display: grid; grid-template-columns: 130px minmax(0, 1fr); gap: 12px; width: 100%; padding: 8px 0; text-align: left; background: transparent; color: var(--text-primary); border: 0; font-size: 13px; }.work-time-track { background: var(--input-bg); align-self: center; height: 12px; }.work-time-track i { display: block; background: var(--blue); height: 100%; }
</style>
