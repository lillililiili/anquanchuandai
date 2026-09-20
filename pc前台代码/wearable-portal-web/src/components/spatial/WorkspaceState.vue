<script setup>
import DataState from '@/components/personnel/DataState.vue'
defineProps({ context: { type: Object, required: true }, availableSite: Boolean, siteId: { type: String, default: '' }, query: { type: Object, required: true }, idle: { type: String, default: '请选择查询条件' } })
defineEmits(['retry'])
</script>
<template>
  <DataState v-if="context.state === 'LOADING' || context.state === 'IDLE'" state="LOADING" />
  <DataState v-else-if="context.state === 'ERROR'" state="ERROR" :message="context.error?.message" retry @retry="context.load(true)" />
  <DataState v-else-if="!availableSite" :state="siteId ? 'FORBIDDEN' : 'NOT_INTEGRATED'" :message="siteId ? '当前厂站无权查看' : context.data?.sites.length ? '请在顶栏选择厂站' : '厂站数据待接入'" />
  <DataState v-else-if="query.state === 'LOADING'" state="LOADING" />
  <div v-else-if="query.error"><DataState :state="query.state" :message="query.error.message" retry @retry="$emit('retry')" /><small class="s2-note">错误码：{{ query.error.errorCode || query.error.code }} · 请求标识：{{ query.error.requestId || '未知' }}</small></div>
  <DataState v-else-if="query.data?.state && query.data.state !== 'AVAILABLE'" :state="query.data.state" :reason="query.data.reasonCode" />
  <DataState v-else-if="query.state === 'IDLE'" state="IDLE" :message="idle" />
  <slot v-else />
</template>
