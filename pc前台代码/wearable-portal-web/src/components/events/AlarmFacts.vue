<script setup>
import { alarmLabel, deviceTypes } from '@/utils/alarm-contract'
import { eventTime } from '@/utils/event-contract'
defineProps({ event: { type: Object, required: true } })
</script>
<template>
  <section class="alarm-facts">
    <h2>{{ event.eventTypeName || event.title }}</h2><span class="event-phase" :class="event.handlingStatus">{{ alarmLabel(event) }}</span>
    <dl><dt>设备类型</dt><dd>{{ deviceTypes[event.deviceType] || '未知' }}</dd><dt>设备编号</dt><dd>{{ event.deviceCode || '未知' }}</dd><dt>设备名称</dt><dd>{{ event.deviceName || '未知' }}</dd>
      <dt>发生时关联人员</dt><dd>{{ event.person?.state === 'AVAILABLE' ? event.person.data.map(p => p.name).join('、') || '未知' : event.person?.state === 'FORBIDDEN' ? '无权查看' : '未知' }}</dd>
      <dt>发生时间</dt><dd>{{ eventTime(event.occurredAt) }}</dd><dt>接收时间</dt><dd>{{ eventTime(event.receivedAt) }}</dd>
      <dt>原始告警内容</dt><dd>{{ event.deviceReport?.description || '来源未提供' }}</dd>
      <dt>原始类型</dt><dd>{{ event.deviceReport?.rawType || '待确认' }}</dd>
      <dt>来源说明</dt><dd>{{ event.deviceReport?.evidence || event.sourceSystem || '未知' }}</dd>
    </dl>
    <template v-if="event.handlingStatus === 'HANDLED'"><h3>处理记录</h3><dl><dt>处理人</dt><dd>{{ event.handledBy?.name || '未知' }}</dd><dt>处理时间</dt><dd>{{ eventTime(event.handledAt) }}</dd><dt>处理说明</dt><dd class="handling-note">{{ event.handlingNote || '来源未提供' }}</dd></dl></template>
    <p class="event-note">处理状态表示人员是否完成告警记录处理，不代表设备异常已恢复。</p>
  </section>
</template>
<style scoped>
.alarm-facts dl { display:grid; grid-template-columns:130px minmax(0,1fr); gap:12px; }
dt { color:var(--text-muted); } dd { margin:0; overflow-wrap:anywhere; }
.handling-note { white-space:pre-wrap; }
.UNHANDLED { color:var(--warning, #e8a442); } .HANDLED { color:var(--success, #29ba98); }
</style>
