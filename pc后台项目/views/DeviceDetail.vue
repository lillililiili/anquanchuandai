<template><section><div class="page-heading"><div><span class="eyebrow">装备资产 / 设备台账 / 档案</span><h1>设备档案</h1></div><router-link class="button" :to="recordReturn(route.query.returnTo, '/admin/assets/devices')">返回设备台账</router-link></div><AssetTabs />
  <QueryState :data="d" :loading="detail.loading.value" :error="detail.error.value" @retry="load"><template v-if="d?.id">
    <section class="panel device-summary" aria-label="设备概况">
      <DeviceMark :type="d.type" />
      <div class="device-summary-info">
        <p class="device-summary-source">{{ DEVICE_TYPES[d.type] }}<span aria-hidden="true">/</span>{{ d.source === 'PLATFORM' ? '厂家同步设备' : '本地资产档案' }}</p>
        <h2>{{ d.name }}</h2>
        <p class="device-summary-code"><span>设备编号</span><strong>{{ d.code }}</strong></p>
        <div class="device-summary-meta"><span>型号 <b>{{ d.modelName || '待补充' }}</b></span><span>所属区域 <b>{{ d.areaName || '未分配区域' }}</b></span></div>
        <div class="device-summary-status">
          <span class="badge">{{ DEVICE_FILTERS.lifecycle[d.lifecycle] }}</span>
          <span class="badge" :class="{ warning: ['UNKNOWN', 'CONFLICT'].includes(d.relation) }">{{ DEVICE_FILTERS.relation[d.relation] }}</span>
          <span class="badge communication-badge" :class="{ 'is-online': d.communication === 'ONLINE' }"><i aria-hidden="true"></i>{{ DEVICE_FILTERS.communication[d.communication] }}</span>
        </div>
      </div>
      <div class="device-summary-operations">
        <p class="device-summary-operations-title">设备操作</p>
        <div class="device-summary-buttons">
          <AssignmentEntry :device-id="String(route.params.deviceId)" :disabled="d.relation !== 'UNASSIGNED' || d.lifecycle !== 'STOCK' || !d.writable" reason="需库存、明确未领用及本设备办理权限" />
          <AssignmentEntry mode="return" :device-id="String(route.params.deviceId)" :disabled="d.relation !== 'ASSIGNED' || !d.person || !d.writable" :reason="d.relation === 'UNASSIGNED' ? '设备尚未领用，无需归还' : '需正常有效关系及双方范围办理权限'" />
          <DeviceEditPanel :device="d" :disabled="!d.writable || detail.loading.value" :reason="d.lifecycle === 'SCRAPPED' ? '报废设备全档案只读' : '需要本设备范围的资产维护权限'" />
        </div>
      </div>
    </section>
    <div class="device-detail-grid"><section class="panel"><h2>基础资料</h2><dl class="record-fields"><template v-for="[key, name] in fields" :key="key"><dt>{{ name }}</dt><dd>{{ d[key] || '待补充' }}</dd></template><dt>厂站</dt><dd>{{ store.sites.find(s => s.id === d.siteId)?.name }}</dd><dt>区域</dt><dd>{{ d.areaName }}</dd><dt>资料版本</dt><dd>{{ d.version }}</dd></dl><p class="notice">{{ d.identityComplete ? '厂家身份已填写，尚未核验真实设备。' : '厂家身份未完整核验，缺少厂商或SN。' }}</p></section>
    <section class="panel"><h2>当前领用关系</h2><p>{{ DEVICE_FILTERS.relation[d.relation] }}</p><template v-if="d.person"><router-link class="button" :to="{ path: '/admin/people/' + d.person.id, query: { siteId: store.siteId } }">{{ d.person.name }} · 人员详情</router-link><p class="muted">{{ d.assignmentSource === 'MOCK_OPERATION' ? '本页本地办理' : '初始领用记录' }} · 领用开始：{{ beijingTime(d.startedAt) }}</p></template><p v-else class="muted">{{ d.relation === 'UNASSIGNED' ? '来源明确未领用。' : '人员关联未知、冲突或无权查看；不推定使用人。' }}</p></section>
    <section class="panel capability-panel"><h2>{{ d.type === 'HELMET' ? '视频通道与定位' : d.type === 'BELT' ? '安全带说明' : '手表说明' }}</h2><p>{{ d.declaration }}</p><dl class="record-fields"><dt>档案说明</dt><dd>{{ d.modelName }}</dd><dt>前台能力</dt><dd>{{ d.type === 'HELMET' ? '视频通道、定位（实时状态在监护前台）' : '无设备上报' }}</dd><dt>通信</dt><dd>{{ DEVICE_FILTERS.communication[d.communication] }}</dd><dt>电量</dt><dd>{{ d.battery == null || d.battery === '' ? '—' : d.battery + '%' }}</dd><dt>来源</dt><dd>{{ d.capabilitySource }}</dd></dl><p v-if="d.type !== 'HELMET'" class="notice">没有设备上报。不显示传感读数，不生成健康或作业安全结论。</p></section>
    <section class="panel"><h2>接入摘要</h2><dl class="record-fields"><dt>通信</dt><dd>{{ DEVICE_FILTERS.communication[d.communication] }}</dd><dt>电量</dt><dd>{{ d.battery == null || d.battery === '' ? '—' : d.battery + '%' }}</dd><dt>数据更新情况</dt><dd>{{ d.source === 'PLATFORM' ? (d.freshness === 'CURRENT' ? '厂家设备列表' : '厂家状态待刷新') : (d.freshness === 'CURRENT' ? '来自监护快照' : '尚未读到快照') }}</dd><dt>快照时间</dt><dd>{{ d.sourceTime || '未知' }}</dd></dl><p class="muted">{{ d.source === 'PLATFORM' ? '通信来自厂家设备列表；电量、定位、佩戴及音视频尚待设备联调。' : '通信和电量来自监护快照，不能在这里修改。定位和视频仍在监护前台查看。' }}</p><a v-if="portal" class="button" :href="portal" target="_blank" rel="noopener noreferrer">打开监护前台首页</a><button v-else class="button" disabled>前台地址未配置</button></section></div>
    <section class="panel device-history"><h2>领用历史</h2><QueryState :data="history.data.value" :loading="history.loading.value" :error="history.error.value" @retry="loadHistory"><HistoryTable :rows="history.data.value?.rows || []" /><div class="pagination"><span>共 {{ history.data.value?.total || 0 }} 条</span><button class="button" :disabled="historyPage <= 1" @click="historyPage--; loadHistory()">上一页历史</button><button class="button" :disabled="historyPage * 20 >= (history.data.value?.total || 0)" @click="historyPage++; loadHistory()">下一页历史</button></div></QueryState></section>
    <section class="panel device-history"><h2>资料变更（需要操作日志查看权限）</h2><QueryState :data="changes.data.value" :loading="changes.loading.value" :error="changes.error.value" @retry="loadChanges"><ol v-if="changes.data.value?.rows?.length" class="device-changes"><li v-for="a in changes.data.value.rows" :key="a.id"><strong>{{ a.action }} · {{ a.actorName }}</strong><p>{{ a.occurredAt }} · {{ a.source }}</p><dl class="record-fields"><template v-for="field in changed(a)" :key="field"><dt>{{ fieldNames[field] || field }}</dt><dd>{{ format(a.before?.[field]) }} → {{ format(a.after?.[field]) }}</dd></template></dl></li></ol><p v-else class="query-state">暂无设备资料变更。</p><div class="pagination"><span>共 {{ changes.data.value?.total || 0 }} 条</span><button class="button" :disabled="changesPage <= 1" @click="changesPage--; loadChanges()">上一页变更</button><button class="button" :disabled="changesPage * 20 >= (changes.data.value?.total || 0)" @click="changesPage++; loadChanges()">下一页变更</button></div></QueryState></section>
  </template></QueryState></section></template>
<script setup>
import { computed, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { useAdminStore } from '../store'
import { useQuery } from '../useQuery'
import { recordReturn, trustedPortal } from '../navigation'
import { beijingTime } from '../tablePresentation'
import { DEVICE_FILTERS, DEVICE_TYPES } from '../deviceData'
import QueryState from '../components/QueryState.vue'
import DeviceEditPanel from '../components/DeviceEditPanel.vue'
import DeviceMark from '../components/DeviceMark.vue'
import AssetTabs from '../components/AssetTabs.vue'
import AssignmentEntry from '../components/AssignmentEntry.vue'
import HistoryTable from '../components/HistoryTable.vue'
const store = useAdminStore(), route = useRoute(), detail = useQuery(), history = useQuery(), changes = useQuery()
const d = computed(() => detail.data.value), historyPage = ref(1), changesPage = ref(1)
const portal = trustedPortal(import.meta.env.VITE_ADMIN_PORTAL_URL || 'http://127.0.0.1:5191/')
const fields = [['id', '设备ID'], ['manufacturer', '厂商'], ['sn', 'SN'], ['assetCode', '资产编号'], ['purchasedOn', '购置日期'], ['remark', '备注']]
const fieldNames = { ...Object.fromEntries(fields), code: '平台编号', name: '名称', modelId: '型号', areaId: '区域', assemblies: '已安装模块', version: '版本', type: '类型' }
const input = () => ({ siteId: store.siteId, id: route.params.deviceId })
function load() { detail.run('device', input()); loadHistory(); loadChanges() }
function loadHistory() { history.run('deviceHistory', { ...input(), pageNum: historyPage.value, pageSize: 20 }) }
function loadChanges() { changes.run('deviceChanges', { ...input(), pageNum: changesPage.value, pageSize: 20 }) }
function changed(a) { return Object.keys(fieldNames).filter(k => JSON.stringify(a.before?.[k]) !== JSON.stringify(a.after?.[k])) }
const format = v => v == null || v === '' ? '未填写' : typeof v === 'object' ? JSON.stringify(v) : String(v)
watch(() => [store.siteId, route.params.deviceId], () => { historyPage.value = 1; changesPage.value = 1; load() }, { immediate: true })
watch(() => store.revision, load)
</script>

<style scoped>
.device-summary { display: grid; grid-template-columns: 140px minmax(0, 1fr) minmax(320px, 380px); align-items: center; gap: 28px; padding: 24px; margin-bottom: 20px; }
.device-summary :deep(.device-mark) { width: 140px; min-width: 0; margin: 0; border-radius: 8px; }
.device-summary :deep(.device-mark img) { width: 100%; height: auto; aspect-ratio: 1; object-fit: contain; }
.device-summary :deep(.device-mark figcaption) { padding: 7px 4px; font-size: 12px; color: var(--muted); background: var(--canvas); }
.device-summary-info { min-width: 0; }
.device-summary-source { display: flex; flex-wrap: wrap; gap: 10px; color: var(--muted); font-size: 12px; margin: 0 0 8px; }
.device-summary-source > span { color: var(--line); }
.device-summary-info h2 { margin: 0 0 12px; font-size: 24px; line-height: 1.35; overflow-wrap: anywhere; }
.device-summary-code { display: flex; align-items: baseline; flex-wrap: wrap; gap: 10px; margin: 0 0 8px; }
.device-summary-code > span, .device-summary-meta { color: var(--muted); font-size: 13px; }
.device-summary-code strong { font-family: var(--font-number); font-size: 16px; font-weight: 500; color: var(--ink); overflow-wrap: anywhere; }
.device-summary-meta { display: flex; flex-wrap: wrap; gap: 8px 24px; }
.device-summary-meta b { font-weight: 400; color: var(--ink); margin-left: 8px; overflow-wrap: anywhere; }
.device-summary-status { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 16px; }
.device-summary-status .badge { padding: 4px 10px; line-height: 1.5; }
.device-summary-status .communication-badge { display: inline-flex; align-items: center; gap: 6px; color: var(--muted); background: var(--canvas); }
.communication-badge i { width: 6px; height: 6px; border-radius: 50%; background: currentColor; }
.device-summary-status .communication-badge.is-online { color: var(--success); background: var(--soft-cyan); }
.device-summary-operations { align-self: stretch; border-left: 1px solid var(--line); padding-left: 24px; display: flex; flex-direction: column; justify-content: center; min-width: 0; }
.device-summary-operations-title { margin: 0 0 12px; color: var(--muted); font-size: 12px; }
.device-summary-buttons { display: grid; grid-template-columns: 1fr 1fr 1.2fr; align-items: start; gap: 12px; }
.device-summary-buttons :deep(.assignment-entry), .device-summary-buttons :deep(.device-edit-entry) { width: 100%; max-width: none; gap: 8px; }
.device-summary-buttons :deep(.button) { width: 100%; min-height: 40px; padding: 8px 10px; white-space: nowrap; }
.device-summary-buttons :deep(.disabled-reason) { color: var(--muted); font-size: 12px; line-height: 1.6; }
.device-summary-buttons :deep(.assignment-entry:first-child > .button:not(:disabled)) { color: var(--card); background: var(--blue); border-color: var(--blue); }
.device-summary-buttons :deep(.assignment-entry:first-child > .button:not(:disabled):hover) { background: var(--blue-dark); border-color: var(--blue-dark); }
@media (max-width: 1200px) {
  .device-summary { grid-template-columns: 120px minmax(0, 1fr); gap: 20px; }
  .device-summary :deep(.device-mark) { width: 120px; }
  .device-summary-operations { grid-column: 1 / -1; border-left: 0; border-top: 1px solid var(--line); padding: 16px 0 0; }
  .device-summary-buttons { max-width: 420px; }
}
@media (max-width: 600px) {
  .device-summary { grid-template-columns: 88px minmax(0, 1fr); gap: 16px; padding: 16px; align-items: start; }
  .device-summary :deep(.device-mark) { width: 88px; }
  .device-summary-info h2 { font-size: 20px; }
  .device-summary-meta { gap: 6px; flex-direction: column; }
  .device-summary-buttons { grid-template-columns: repeat(2, minmax(0, 1fr)); }
}
</style>
