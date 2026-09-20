<script setup>
import { computed } from 'vue'
import DataState from '@/components/personnel/DataState.vue'
import VectorMap from '@/components/spatial/VectorMap.vue'
import VideoPlayer from '@/components/video/VideoPlayer.vue'
import { positionReason } from '@/utils/spatial-contract'
import { eventTime } from '@/utils/event-contract'
defineProps({ detail: { type: Object, required: true }, siteId: { type: String, required: true } })
const mediaStub = computed(() => ({ name: '事件影像', video: { state: 'UNKNOWN', verification: 'UNVERIFIED' } }))
</script>
<template><div class="event-scene"><section class="event-section"><h3>事件位置</h3><template v-if="detail.location.state === 'AVAILABLE'"><VectorMap :points="[detail.location.data]" :message="positionReason(detail.location.data)" /><p class="event-note">{{ positionReason(detail.location.data) }} · {{ eventTime(detail.location.data.sourceTime) }}</p></template><DataState v-else :state="detail.location.state" :reason="detail.location.reasonCode" compact /></section><section class="event-section"><h3>现场影像证据</h3><VideoPlayer :device="mediaStub" compact /><DataState v-if="detail.video.state !== 'AVAILABLE'" :state="detail.video.state" :reason="detail.video.reasonCode" compact /><template v-else><router-link v-for="v in detail.video.data" :key="v.id" class="event-link" :to="{ path: '/video/' + v.id, query: { siteId } }">{{ v.name }} · 查看当前设备单路监看 ↗</router-link></template><p class="event-note">当前设备监看不是事件发生时录像；真实拉流未开放。</p></section></div></template>
