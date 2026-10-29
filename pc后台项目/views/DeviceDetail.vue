<template><section><h1 class="sr-only">设备档案</h1><div class="section-heading"><router-link class="button" :to="recordReturn(route.query.returnTo, '/devices')">返回设备台账</router-link></div><AssetTabs />
  <QueryState :data="d" :loading="detail.loading.value" :error="detail.error.value" @retry="load"><template v-if="d?.id">
    <section class="panel device-summary" aria-label="设备概况">
      <DeviceMark :type="d.type" />
      <div class="device-summary-info">
        <p class="device-summary-source">{{ DEVICE_TYPES[d.type] }}<span aria-hidden="true">/</span>{{ d.source === 'DEMO_WATCH' ? '智能手表 · 模拟数据' : d.source === 'DIRECT_BELT' ? '安全带直连' : d.source === 'DIRECT_HELMET' ? '一体式安全帽直连' : d.source === 'PLATFORM' ? '厂家同步设备' : '本地资产档案' }}</p>
        <h2>{{ d.name }}</h2>
        <p class="device-summary-code"><span>设备编号</span><strong>{{ d.code }}</strong></p>
        <div class="device-summary-meta"><span>型号 <b>{{ d.modelName || '待补充' }}</b></span></div>
        <div class="device-summary-status">
          <span class="badge">{{ DEVICE_FILTERS.lifecycle[d.lifecycle] }}</span>
          <span class="badge" :class="{ warning: ['UNKNOWN', 'CONFLICT'].includes(d.relation) }">{{ DEVICE_FILTERS.relation[d.relation] }}</span>
          <span class="badge communication-badge" :class="{ 'is-online': d.communication === 'ONLINE' }"><i aria-hidden="true"></i>{{ DEVICE_FILTERS.communication[d.communication] }}</span>
        </div>
      </div>
      <div class="device-summary-operations">
        <p class="device-summary-operations-title">设备操作</p>
        <div class="device-summary-buttons">
          <AssignmentEntry primary compact :device-id="String(route.params.deviceId)" :disabled="d.relation !== 'UNASSIGNED' || d.lifecycle !== 'STOCK' || !d.writable" reason="需库存、明确未领用及本设备办理权限" />
          <AssignmentEntry mode="return" :device-id="String(route.params.deviceId)" :disabled="d.relation !== 'ASSIGNED' || !d.person || !d.writable" :reason="d.relation === 'UNASSIGNED' ? '设备尚未领用，无需归还' : '需正常有效关系及双方范围办理权限'" />
          <DeviceEditPanel :device="d" :disabled="!d.writable || detail.loading.value" :reason="d.lifecycle === 'SCRAPPED' ? '报废设备全档案只读' : '需要本设备范围的资产维护权限'" />
        </div>
      </div>
    </section>
    <div class="device-detail-grid"><section class="panel"><h2>基础资料</h2><dl class="record-fields"><template v-for="[key, name] in fields" :key="key"><dt>{{ name }}</dt><dd>{{ d[key] || '待补充' }}</dd></template><dt>厂站</dt><dd>{{ store.sites.find(s => s.id === d.siteId)?.name }}</dd></dl><p class="notice">{{ verified.identity }}</p></section>
    <section class="panel"><h2>当前领用关系</h2><p>{{ DEVICE_FILTERS.relation[d.relation] }}</p><template v-if="d.person"><router-link class="button" :to="{ path: '/people/' + d.person.id, query: { siteId: store.siteId } }">{{ d.person.name }} · 人员详情</router-link><p class="muted">{{ d.assignmentSource === 'MOCK_OPERATION' ? '本页本地办理' : '初始领用记录' }} · 领用开始：{{ beijingTime(d.startedAt) }}</p></template><p v-else class="muted">{{ d.relation === 'UNASSIGNED' ? '来源明确未领用。' : '人员关联未知、冲突或无权查看；不推定使用人。' }}</p></section>
    </div>
    <section v-if="d.source === 'DIRECT_BELT'" class="panel"><h2>安全带上报</h2><dl class="record-fields"><dt>佩戴状态</dt><dd>{{ beltState(d.worn, '已佩戴', '未佩戴') }}</dd><dt>佩戴原始值</dt><dd>{{ rawStatus(d.isWeared) }}</dd><dt>A挂钩状态</dt><dd>{{ beltState(d.hookAEngaged, '已挂扣', '未挂扣') }}</dd><dt>A挂钩原始值</dt><dd>{{ rawStatus(d.hangerAStatus) }}</dd><dt>B挂钩状态</dt><dd>{{ beltState(d.hookBEngaged, '已挂扣', '未挂扣') }}</dd><dt>B挂钩原始值</dt><dd>{{ rawStatus(d.hangerBStatus) }}</dd><dt>上报时间</dt><dd>{{ d.deviceReportedAt || d.sourceTime || '尚未上报' }}</dd></dl><p class="notice">原始值保留厂家上报内容；状态值含义确认前显示为待确认。建档和收到上报均不等于完成真实设备安全验证。</p></section>
    <section v-if="d.source === 'DIRECT_HELMET'" class="panel" aria-label="安全帽上报">
      <h2>安全帽上报</h2>
      <dl class="record-fields">
        <dt>电量</dt><dd>{{ verified.battery }}</dd>
        <dt>电量上报时间</dt><dd>{{ d.batteryReportedAt ? beijingTime(d.batteryReportedAt) : '尚未上报' }}</dd>
        <dt>佩戴状态</dt><dd>{{ verified.worn }}</dd>
        <dt>佩戴上报时间</dt><dd>{{ d.isWearedReportedAt ? beijingTime(d.isWearedReportedAt) : '尚未上报' }}</dd>
        <dt>最近通信时间</dt><dd>{{ d.lastSeenAt ? beijingTime(d.lastSeenAt) : '尚未上报' }}</dd>
      </dl>
      <p class="muted">电量和佩戴状态按各自上报时间更新；过期数据不作为当前状态。</p>
    </section>
    <section v-if="hasDeviceEvents" class="panel device-history" aria-label="当前设备报警">
      <h2>设备报警</h2>
      <p class="muted">仅显示当前设备在本厂站内有权查看的报警。报警发生时的记录与设备当前状态分别保留。</p>
      <QueryState :data="deviceEvents.data.value" :loading="deviceEvents.loading.value" :error="deviceEvents.error.value" @retry="loadDeviceEvents">
        <ol v-if="deviceEvents.data.value?.rows?.length" class="device-event-list">
          <li v-for="event in deviceEvents.data.value.rows" :key="event.id">
            <div class="device-event-heading"><strong>{{ event.alarmName || event.title || '设备告警' }}</strong><span class="badge">{{ event.status || '状态未知' }}</span></div>
            <dl class="record-fields">
              <dt>事件编号</dt><dd>{{ event.id }}</dd>
              <dt>设备编号</dt><dd>{{ event.deviceId || d.deviceNumber || '未知' }}</dd>
              <dt>发生时间</dt><dd>{{ event.createdAt ? beijingTime(event.createdAt) : [event.date, event.time].filter(Boolean).join(' ') || '未提供' }}</dd>
              <dt>报警类型</dt><dd>{{ event.type || '待确认' }}</dd>
              <dt>报警代码</dt><dd>{{ event.alarmCode ?? '未提供' }}</dd>
              <dt>设备原始码</dt><dd>{{ rawStatus(event.rawAlarmType) }}</dd>
              <dt>来源</dt><dd>{{ eventSource(event) }}</dd>
              <dt v-if="event.sourceEventId">来源编号</dt><dd v-if="event.sourceEventId">{{ event.sourceEventId }}</dd>
            </dl>
          </li>
        </ol>
        <p v-else class="query-state">当前设备暂无可查看的报警记录。</p>
        <AdminPagination :total="deviceEvents.data.value?.total || 0" :model-value="eventsPage" :page-size="eventsSize" :disabled="deviceEvents.loading.value" @update:model-value="eventsPage=$event; loadDeviceEvents()" @update:page-size="eventsSize=$event; eventsPage=1; loadDeviceEvents()" />
      </QueryState>
    </section>
    <section class="panel device-history"><h2>领用历史</h2><QueryState :data="history.data.value" :loading="history.loading.value" :error="history.error.value" @retry="loadHistory"><HistoryTable :rows="history.data.value?.rows || []" /><AdminPagination :total="history.data.value?.total || 0" :model-value="historyPage" :page-size="historySize" :disabled="history.loading.value" @update:model-value="historyPage=$event; loadHistory()" @update:page-size="historySize=$event; historyPage=1; loadHistory()" /></QueryState></section>
  </template></QueryState></section></template>
<script setup>
import { computed, onUnmounted, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { useAdminStore } from '../store'
import { useQuery } from '../useQuery'
import { recordReturn } from '../navigation'
import { beijingTime } from '../tablePresentation'
import { DEVICE_FILTERS, DEVICE_TYPES } from '../deviceData'
import { verifiedDeviceSummary } from '../devicePresentation'
import QueryState from '../components/QueryState.vue'
import DeviceEditPanel from '../components/DeviceEditPanel.vue'
import DeviceMark from '../components/DeviceMark.vue'
import AssetTabs from '../components/AssetTabs.vue'
import AssignmentEntry from '../components/AssignmentEntry.vue'
import HistoryTable from '../components/HistoryTable.vue'
const store = useAdminStore(), route = useRoute(), detail = useQuery(), history = useQuery(), deviceEvents = useQuery()
const d = computed(() => detail.data.value), historyPage = ref(1), historySize = ref(10), eventsPage = ref(1), eventsSize = ref(10)
const verified = computed(() => verifiedDeviceSummary(d.value))
const hasDeviceEvents = computed(() => ['DIRECT_BELT', 'DIRECT_HELMET'].includes(d.value?.source))
const eventSource = event => event.source === 'device' && event.protocol === 'direct-helmet' ? '安全帽真实上报' : event.source === 'device' && event.protocol === 'direct-belt' ? '安全带真实上报' : event.source || '来源未提供'
const fields = [['id', '设备ID'], ['manufacturer', '厂商'], ['sn', 'SN'], ['assetCode', '资产编号'], ['purchasedOn', '购置日期'], ['remark', '备注']]
const rawStatus = value => value == null || value === '' ? '尚未上报' : String(value)
const beltState = (value, yes, no) => d.value?.freshness !== 'CURRENT' ? '未知（暂无最新上报）' : value === true ? yes : value === false ? no : '待确认'
const input = () => ({ siteId: store.siteId, id: route.params.deviceId })
async function loadDeviceAndEvents(background = false) {
  const requested = input()
  await detail.run('device', requested, { background })
  if (requested.siteId === store.siteId && requested.id === route.params.deviceId && hasDeviceEvents.value) loadDeviceEvents(background)
}
function load() { loadDeviceAndEvents(); loadHistory() }
async function loadDeviceEvents(background = false) {
  await deviceEvents.run('deviceEvents', { ...input(), pageNum: eventsPage.value, pageSize: eventsSize.value }, { background: background === true })
  const total = deviceEvents.data.value?.total
  if (total != null && eventsPage.value > Math.max(1, Math.ceil(total / eventsSize.value))) {
    eventsPage.value = Math.max(1, Math.ceil(total / eventsSize.value)); loadDeviceEvents()
  }
}
async function loadHistory() { await history.run('deviceHistory', { ...input(), pageNum: historyPage.value, pageSize: historySize.value }); const total=history.data.value?.total; if(total != null && historyPage.value > Math.max(1,Math.ceil(total/historySize.value))) { historyPage.value=Math.max(1,Math.ceil(total/historySize.value)); loadHistory() } }
watch(() => [store.siteId, route.params.deviceId], () => { historyPage.value = 1; eventsPage.value = 1; deviceEvents.cancel(); load() }, { immediate: true })
watch(() => store.revision, load)
const refreshTimer=setInterval(()=>{if(!detail.loading.value && !detail.refreshing.value && !deviceEvents.loading.value && !deviceEvents.refreshing.value)loadDeviceAndEvents(true)},15000)
onUnmounted(()=>clearInterval(refreshTimer))
</script>

<style scoped>
.device-event-list { list-style: none; padding: 0; margin: 0; }
.device-event-list > li { padding: 16px 0; border-bottom: 1px solid var(--line); }
.device-event-list > li:last-child { border-bottom: 0; }
.device-event-heading { display: flex; align-items: baseline; justify-content: space-between; flex-wrap: wrap; gap: 8px; }
.device-event-list dd { overflow-wrap: anywhere; }
.device-summary { display: grid; grid-template-columns: 140px minmax(0, 1fr) minmax(320px, 380px); align-items: center; gap: 28px; padding: 24px; margin-bottom: 20px; }
.device-summary :deep(.device-mark) { width: 140px; min-width: 0; margin: 0; border-radius: 8px; }
.device-summary :deep(.device-mark img) { width: 100%; height: auto; aspect-ratio: 1; object-fit: contain; }
.device-summary :deep(.device-mark figcaption) { padding: 7px 4px; font-size:12px; color: var(--muted); background: var(--canvas); }
.device-summary-info { min-width: 0; }
.device-summary-source { display: flex; flex-wrap: wrap; gap: 10px; color: var(--muted); font-size:12px; margin: 0 0 8px; }
.device-summary-source > span { color: var(--line); }
.device-summary-info h2 { margin: 0 0 12px; font-size:24px; line-height: 1.35; overflow-wrap: anywhere; }
.device-summary-code { display: flex; align-items: baseline; flex-wrap: wrap; gap: 10px; margin: 0 0 8px; }
.device-summary-code > span, .device-summary-meta { color: var(--muted); font-size:12px; }
.device-summary-code strong { font-family: var(--font-number); font-size:16px; font-weight: 500; color: var(--ink); overflow-wrap: anywhere; }
.device-summary-meta { display: flex; flex-wrap: wrap; gap: 8px 24px; }
.device-summary-meta b { font-weight: 400; color: var(--ink); margin-left: 8px; overflow-wrap: anywhere; }
.device-summary-status { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 16px; }
.device-summary-status .badge { padding: 4px 10px; line-height: 1.5; }
.device-summary-status .communication-badge { display: inline-flex; align-items: center; gap: 6px; color: var(--muted); background: var(--canvas); }
.communication-badge i { width: 6px; height: 6px; border-radius: 50%; background: currentColor; }
.device-summary-status .communication-badge.is-online { color: var(--success); background: var(--soft-cyan); }
.device-summary-operations { align-self: stretch; border-left: 1px solid var(--line); padding-left: 24px; display: flex; flex-direction: column; justify-content: center; min-width: 0; }
.device-summary-operations-title { margin: 0 0 12px; color: var(--muted); font-size:12px; }
.device-summary-buttons { display: grid; grid-template-columns: 1fr 1fr 1.2fr; align-items: start; gap: 12px; }
.device-summary-buttons :deep(.assignment-entry), .device-summary-buttons :deep(.device-edit-entry) { width: 100%; max-width: none; gap: 8px; }
.device-summary-buttons :deep(.button) { width: 100%; min-height: 40px; padding: 8px 10px; white-space: nowrap; }
.device-summary-buttons :deep(.disabled-reason) { color: var(--muted); font-size:12px; line-height: 1.6; }
@media (max-width: 1200px) {
  .device-summary { grid-template-columns: 120px minmax(0, 1fr); gap: 20px; }
  .device-summary :deep(.device-mark) { width: 120px; }
  .device-summary-operations { grid-column: 1 / -1; border-left: 0; border-top: 1px solid var(--line); padding: 16px 0 0; }
  .device-summary-buttons { max-width: 420px; }
}
@media (max-width: 600px) {
  .device-summary { grid-template-columns: 88px minmax(0, 1fr); gap: 16px; padding: 16px; align-items: start; }
  .device-summary :deep(.device-mark) { width: 88px; }
  .device-summary-info h2 { font-size:18px; }
  .device-summary-meta { gap: 6px; flex-direction: column; }
  .device-summary-buttons { grid-template-columns: repeat(2, minmax(0, 1fr)); }
}
</style>
