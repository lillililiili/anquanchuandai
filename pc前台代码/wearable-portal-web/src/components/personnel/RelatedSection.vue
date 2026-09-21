<script setup>
import { alarmLabel } from '@/utils/alarm-contract'
import { formatTime } from '@/utils/portal-contract'
import DataState from './DataState.vue'
defineProps({ section: { type: Object, required: true }, kind: { type: String, default: 'works' } })
</script>
<template>
  <DataState v-if="section.state !== 'AVAILABLE'" :state="section.state" :reason="section.reasonCode" compact />
  <DataState v-else-if="!section.data?.length" state="EMPTY" compact />
  <div v-else class="related-records">
    <article v-for="(item, index) in section.data" :key="item.workId || item.eventId || index">
      <router-link v-if="kind === 'works' && item.monitorState" :to="{ path: '/supervision/' + item.workId, query: { siteId: item.siteId } }">查看作业监护 →</router-link><p v-if="item.monitorState">本地监护：{{ { PENDING: '待开始', ACTIVE: '监护中', PAUSED: '暂停', ENDED: '已结束' }[item.monitorState] }} · {{ item.participantCount }} 人 · 未处理告警 {{ item.openEventCount ?? '未知' }} 件 · 本地监护人 {{ item.localSupervisorName || '尚未安排' }}</p><strong>{{ item.name || item.title || '—' }}</strong>
      <dl v-if="kind === 'works'" class="person-facts"><dt>作业单号</dt><dd>{{ item.sourceWorkNo || '—' }}</dd><dt>所属区域</dt><dd>{{ item.area?.name || '—' }}</dd><dt>当前岗位</dt><dd>{{ item.personRole || '—' }}</dd><dt>监护人</dt><dd>{{ item.supervisor?.name || '—' }}</dd><dt>负责人</dt><dd>{{ item.responsible?.name || '—' }}</dd><dt>作业时段</dt><dd>{{ formatTime(item.startsAt) }} ～ {{ formatTime(item.endsAt) }}</dd><dt>来源</dt><dd>{{ item.source || '—' }}</dd></dl>
      <router-link v-else :to="{ path: '/alarms/' + item.eventId, query: { siteId: item.siteId } }">查看告警详情 →</router-link><p v-if="kind === 'events'" class="muted">{{ formatTime(item.occurredAt) }} · {{ alarmLabel(item) }}</p>
    </article>
  </div>
</template>
