<script setup>
import DataState from '@/components/personnel/DataState.vue'
import { eventTime } from '@/utils/event-contract'
defineProps({ section: { type: Object, default: null }, siteId: { type: String, default: '' } })
</script>
<template><div class="event-evidence"><DataState v-if="section?.state !== 'AVAILABLE'" :state="section?.state" :reason="section?.reasonCode" compact /><DataState v-else-if="!section.data.length" state="EMPTY" compact /><ul v-else><li v-for="e in section.data" :key="e.id"><div class="event-media-placeholder">证据预览未开放</div><strong>{{ e.name }}</strong><small v-if="e.associationSource === 'MANUAL_MOCK'">人工关联 · 非历史佩戴证据{{ e.frozen ? ' · 已冻结版本' : '' }}</small><small>{{ e.type || '类型未知' }} · {{ e.id }}</small><small>版本：{{ e.version || '未知' }} · 内容摘要：{{ e.digest || '未知' }}</small><small>采集：{{ eventTime(e.capturedAt) }}</small><small>接收：{{ eventTime(e.receivedAt) }}</small><router-link class="event-link" :to="{ path: '/materials', query: { siteId, selectedId: e.id } }">查看授权资料元数据 ↗</router-link></li></ul><p class="event-note">本区仅展示授权元数据；内存文件可进入现场资料查看，真实文件访问未开放。</p></div></template>
