<script setup>
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import { useEventWorkspace } from '@/composables/useEventWorkspace'
import { safeEventReturn } from '@/utils/event-route'
import { writable } from '@alarm-provider'
import EventActions from '@event-actions'
import ContactEntry from '@contact-entry'
import WorkspaceState from '@/components/spatial/WorkspaceState.vue'
import AlarmFacts from '@/components/events/AlarmFacts.vue'
import EventScene from '@/components/events/EventScene.vue'
const route = useRoute(), eventId = computed(() => String(route.params.eventId || ''))
const { context, siteId, availableSite, detail, reloadDetail } = useEventWorkspace(eventId)
const returnTo = computed(() => safeEventReturn(route.query.returnTo))
</script>
<template>
  <div class="event-workspace">
    <header class="event-heading"><div><h1>告警详情</h1><p>{{ writable ? '模拟设备上报 · 处理后保留记录' : '来源查询 · 处理状态与写入待接入' }}</p></div><router-link class="event-button" :to="returnTo">← 返回来源页面</router-link></header>
    <WorkspaceState :context="context" :site-id="siteId" :available-site="availableSite" :query="detail" @retry="reloadDetail">
      <template v-if="detail.data?.event"><AlarmFacts :event="detail.data.event" /><div class="alarm-detail-actions"><EventActions :event="detail.data.event" :site-id="siteId" /><button v-if="!writable" class="event-button" disabled title="真实处理接口未接入">处理未开放</button><ContactEntry :site-id="siteId" :device-id="detail.data.event.deviceId" :event-id="eventId" /></div><EventScene :detail="detail.data" :site-id="siteId" /></template>
      <p v-else>告警来源未接入，暂时无法查看详情。</p>
    </WorkspaceState>
  </div>
</template>
<style scoped>.alarm-detail-actions { display:flex; align-items:center; flex-wrap:wrap; gap:12px; margin:20px 0; }
.alarm-detail-actions :deep(.dispatch-entry) { display:inline-flex; align-items:center; justify-content:center; box-sizing:border-box; min-height:40px; margin:0; padding:0 16px; border-radius:6px; line-height:1.4; }</style>
