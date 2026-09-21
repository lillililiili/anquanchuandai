<script setup>
import { computed, reactive, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useEventWorkspace } from '@/composables/useEventWorkspace'
import { usePortalQuery } from '@/composables/usePortalQuery'
import { useBusinessRevision } from '@/composables/useBusinessRevision'
import { getEvents, writable } from '@alarm-provider'
import { eventQuery, eventTimeZone, eventLocalToUtc, eventLocalTime } from '@/utils/event-route'
import { eventTime } from '@/utils/event-contract'
import { alarmLabel, deviceTypes } from '@/utils/alarm-contract'
import WorkspaceState from '@/components/spatial/WorkspaceState.vue'
import DataState from '@/components/personnel/DataState.vue'
import EventActions from '@event-actions'
const route = useRoute(), router = useRouter(), list = reactive(usePortalQuery())
const query = computed(() => eventQuery(route.query)), selectedId = computed(() => '')
const { context, user, siteId, availableSite } = useEventWorkspace(selectedId)
const status = computed(() => query.value.handlingStatus || 'UNHANDLED')
const zone = computed(() => eventTimeZone(context.data?.sites.find(s => s.siteId === siteId.value)?.timeZone))
const form = reactive({ keyword: '', deviceType: '', eventType: '', from: '', to: '', error: '' })
const params = computed(() => ({ ...query.value, selectedId: undefined, siteId: siteId.value, handlingStatus: writable ? status.value : undefined, pageNum: Number(query.value.pageNum || 1), pageSize: Number(query.value.pageSize || 20) }))
function reload() { if (!availableSite.value) return list.clear(); list.run(s => getEvents(params.value, s)) }
watch(() => JSON.stringify([params.value, availableSite.value, user.token]), reload, { immediate: true })
watch([query, zone], ([q]) => { Object.assign(form, { keyword: q.keyword || '', deviceType: q.deviceType || '', eventType: q.eventType || '', from: q.from ? eventLocalTime(q.from, zone.value) : '', to: q.to ? eventLocalTime(q.to, zone.value) : '', error: '' }) }, { immediate: true })
useBusinessRevision(['events'], reload)
function navigate(values) { router.push({ path: '/alarms', query: eventQuery({ ...query.value, siteId: siteId.value, ...values, selectedId: undefined }) }) }
function search(reset = false) {
  try {
    form.error = ''
    const from = reset ? null : eventLocalToUtc(form.from, zone.value), to = reset ? null : eventLocalToUtc(form.to, zone.value)
    if (!!from !== !!to || from && from >= to) throw new Error('请填写完整且开始早于结束的时间范围')
    navigate({ keyword: reset ? '' : form.keyword, deviceType: reset ? '' : form.deviceType, eventType: reset ? '' : form.eventType, from, to, pageNum: '1' })
  } catch (e) { form.error = e.message }
}
const types = computed(() => (list.data?.filters.eventTypes.data || []).filter(t => !form.deviceType || !t.deviceType || t.deviceType === form.deviceType))
const detailTarget = e => ({ path: '/alarms/' + e.eventId, query: { siteId: siteId.value, returnTo: route.fullPath } })
watch(() => route.query.selectedId, id => { if (typeof id === 'string' && /^[\w-]+$/.test(id)) router.replace({ path: '/alarms/' + id, query: { siteId: siteId.value, returnTo: router.resolve({ path: '/alarms', query: { siteId: siteId.value } }).fullPath } }) }, { immediate: true })
</script>
<template>
  <div class="event-workspace alarm-workspace">
    <header class="event-heading"><div><h1>告警事件</h1><p>{{ writable ? '安全帽 · 安全带 · 手表 / 模拟设备告警' : '来源查询；处理状态待确认，真实处理接口未接入' }}</p></div><button class="event-button" :disabled="!availableSite || list.state === 'LOADING'" @click="reload">刷新</button></header>
    <div v-if="writable" class="alarm-tabs" role="group" aria-label="告警处理状态"><button v-for="(label, value) in { UNHANDLED: '未处理', HANDLED: '已处理' }" :key="value" class="event-button" :class="{ primary: status === value }" :aria-pressed="status === value" @click="navigate({ handlingStatus: value, pageNum: '1' })">{{ label }}</button></div>
    <form class="event-filters" @submit.prevent="search()">
      <label>设备类型<select aria-label="设备类型" v-model="form.deviceType" :disabled="!writable" @change="form.eventType = ''"><option value="">全部装备</option><option v-for="(label, value) in deviceTypes" :key="value" :value="value">{{ label }}</option></select></label>
      <label>告警类型<select aria-label="告警类型" v-model="form.eventType" :disabled="list.data?.filters.eventTypes.state !== 'AVAILABLE'"><option value="">全部类型</option><option v-for="t in types" :key="t.value" :value="t.value">{{ t.label }}</option></select></label>
      <label>{{ writable ? '设备编号 / 人员姓名' : '设备编号' }}<input v-model="form.keyword" maxlength="100" :placeholder="writable ? '输入编号或姓名' : '输入设备编号'"></label>
      <label>发生时间起<input v-model="form.from" type="datetime-local" step="1"></label><label>发生时间止<input v-model="form.to" type="datetime-local" step="1"></label>
      <button class="event-button primary" :disabled="!availableSite">查询</button><button type="button" class="event-button" @click="search(true)">重置</button>
    </form>
    <p class="event-note">时间筛选使用 {{ zone }}，结束时间不包含在区间内。</p><p v-if="form.error" role="alert">{{ form.error }}</p>
    <WorkspaceState :context="context" :site-id="siteId" :available-site="availableSite" :query="list" @retry="reload">
      <div class="event-table-panel">
        <div class="event-table-scroll"><table class="event-table"><thead><tr><th>告警类型</th><th>设备类型</th><th>设备编号</th><th>发生时关联人员</th><th>发生时间</th><th>处理状态</th><template v-if="writable && status === 'HANDLED'"><th>处理人</th><th>处理时间</th><th>处理说明</th></template><th>操作</th></tr></thead>
          <tbody><tr v-for="e in list.data?.items || []" :key="e.eventId"><td><strong>{{ e.eventTypeName || e.title }}</strong><small>{{ e.eventId }}</small></td><td>{{ deviceTypes[e.deviceType] || '未知' }}</td><td>{{ e.deviceCode || '未知' }}</td><td>{{ e.person?.state === 'AVAILABLE' ? e.person.data.map(p => p.name).join('、') || '未知' : e.person?.state === 'FORBIDDEN' ? '无权查看' : '未知' }}</td><td>{{ eventTime(e.occurredAt) }}</td><td><span class="event-phase" :class="e.handlingStatus">{{ alarmLabel(e) }}</span></td><template v-if="writable && status === 'HANDLED'"><td>{{ e.handledBy?.name || '未知' }}</td><td>{{ eventTime(e.handledAt) }}</td><td><span class="alarm-note" :title="e.handlingNote">{{ e.handlingNote }}</span></td></template><td><div class="alarm-row-actions"><router-link class="event-button" :to="detailTarget(e)">查看详情</router-link><EventActions :event="e" :site-id="siteId" /></div></td></tr></tbody>
        </table></div>
        <DataState v-if="!list.data?.items.length" state="EMPTY" message="当前筛选范围暂无告警" />
        <footer class="event-pagination"><AppPagination v-if="list.data?.total" :current-page="params.pageNum" :page-size="params.pageSize" :total="list.data.total" @current-change="navigate({ pageNum: String($event) })" /></footer>
      </div>
    </WorkspaceState>
    <p v-if="writable" class="event-note">模拟操作仅保存在本页内存，刷新恢复预置记录；已处理不代表设备异常已恢复。</p>
  </div>
</template>
<style scoped>
.alarm-tabs { display:flex; gap:10px; margin:16px 0; }
.alarm-row-actions { display:flex; gap:8px; white-space:nowrap; }
.alarm-note { display:block; max-width:260px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
.UNHANDLED { color:var(--warning, #e8a442); } .HANDLED { color:var(--success, #29ba98); }
.event-table { min-width:1050px; } .event-table td { vertical-align:middle; }
</style>
