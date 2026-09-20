<script setup>
import DataState from '@/components/personnel/DataState.vue'
import { deviceTypes, labels } from '@/utils/portal-contract'
import { eventTime } from '@/utils/event-contract'
defineProps({ section: { type: Object, default: null } })
</script>
<template><section class="event-section"><h3>关联装备状态</h3><DataState v-if="section?.state !== 'AVAILABLE'" :state="section?.state" :reason="section?.reasonCode" compact /><div class="event-equipment"><div v-for="(name, type) in deviceTypes" :key="type"><strong>{{ name }}</strong><template v-if="section?.state === 'AVAILABLE' && section.data.some(r => r.deviceType === type.toUpperCase())"><div v-for="r in section.data.filter(r => r.deviceType === type.toUpperCase())" :key="r.id + r.snapshotKind"><span>{{ r.name }}</span><small>{{ r.snapshotKind === 'HISTORICAL' ? '事件时快照' : r.snapshotKind === 'CURRENT' ? '当前状态，不代表事件时状态' : '快照时点未知' }}</small><small>{{ labels[r.communication] || '通信未知' }} · {{ eventTime(r.sourceTime) }}</small></div></template><small v-else>事件时装备状态未知</small><small v-if="type !== 'helmet'">厂家能力待确认</small></div></div><p class="event-note">当前绑定不能证明事件发生时的领用关系。</p></section></template>
