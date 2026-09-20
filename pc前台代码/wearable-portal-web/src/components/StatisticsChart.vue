<script setup>
import { computed } from 'vue'
const props = defineProps({ metrics: { type: Array, default: () => [] }, title: { type: String, required: true } })
defineEmits(['select'])
const maximum = computed(() => Math.max(1, ...props.metrics.map(m => m.count || 0)))
</script>
<template><section class="stat-chart" :aria-label="title"><h2>{{ title }}</h2><p>单位：条 / 个 · 点击或按 Enter 查看同口径明细；条长相对于当前最大值。</p><p v-if="!metrics.length">此范围暂无可绘制记录；未知日期不补零。</p><button v-for="m in metrics" :key="m.id" :disabled="m.state !== 'AVAILABLE'" @click="$emit('select', m)"><span>{{ m.label }}</span><span class="bar-track" aria-hidden="true"><i :style="{ width: ((m.count || 0) / maximum * 100) + '%' }" /></span><strong>{{ m.count ?? '未知' }}</strong></button></section></template>
<style scoped>
.stat-chart{padding:20px;border:1px solid var(--border);background:var(--panel-bg);min-width:0}.stat-chart h2{font-size:19px;margin:0}.stat-chart p{color:var(--text-secondary);font-size:13px}.stat-chart button{display:grid;grid-template-columns:minmax(100px,180px) 1fr 60px;gap:16px;align-items:center;width:100%;padding:12px 0;background:transparent;color:var(--text-primary);border:0;text-align:left}.bar-track{height:10px;background:var(--input-bg);min-width:0}.bar-track i{display:block;height:100%;background:var(--cyan)}strong{font-family:Consolas,monospace;text-align:right}button:focus-visible{outline:2px solid var(--cyan);outline-offset:3px}button span{overflow-wrap:anywhere}
</style>
