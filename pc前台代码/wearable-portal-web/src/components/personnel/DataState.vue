<script setup>
import { computed } from 'vue'
import { labels, reasons } from '@/utils/portal-contract'
import AppIcon from '@/components/AppIcon.vue'
const props = defineProps({ state: { type: String, default: 'NOT_INTEGRATED' }, reason: { type: String, default: '' }, message: { type: String, default: '' }, compact: Boolean, retry: Boolean })
defineEmits(['retry'])
const text = computed(() => props.message || reasons[props.reason] || ({ LOADING: '正在读取数据…', IDLE: '请选择人员', EMPTY: '暂无记录', ERROR: '数据读取失败' }[props.state]) || labels[props.state] || '数据待接入')
const icon = computed(() => ({ LOADING: 'Refresh', FORBIDDEN: 'Lock', ERROR: 'Warning', IDLE: 'View', NOT_INTEGRATED: 'OfficeBuilding' }[props.state] || 'Document'))
</script>
<template><div class="data-state" :class="{ compact }" :data-state="state" role="status" :aria-busy="state === 'LOADING'"><span class="state-mark" aria-hidden="true"><AppIcon :name="icon" :size="compact ? 20 : 28" /></span><p>{{ text }}</p><small v-if="state === 'NOT_INTEGRATED'">接入有效数据后显示，不使用示例值替代</small><el-button v-if="retry" size="small" @click="$emit('retry')">重新读取</el-button></div></template>
