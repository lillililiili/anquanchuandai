<script setup>
import DataState from '@/components/personnel/DataState.vue'
import { deliveryLabels, eventTime } from '@/utils/event-contract'
defineProps({ title: { type: String, required: true }, section: { type: Object, default: null }, original: Boolean })
</script>
<template><section class="event-section"><h3>{{ title }}</h3><DataState v-if="section?.state !== 'AVAILABLE'" :state="section?.state" :reason="section?.reasonCode" compact /><template v-else><p>{{ original ? section.data.status || '原系统状态未知' : deliveryLabels[section.data.state] }}</p><small>{{ original ? section.data.sourceEventId || '来源编号未知' : section.data.receiptId || '回执未知' }}</small><small>{{ eventTime(section.data.sourceTime) }}</small><p v-if="section.data.reason" class="event-note">{{ section.data.reason }}</p></template><p v-if="original" class="event-note">原系统状态只读；本地跟进不代表原系统结案。</p></section></template>
