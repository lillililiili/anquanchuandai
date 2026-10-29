<template>
  <section>
    <h1 class="sr-only">操作日志</h1>
    <p v-if="exportError" class="error" role="alert">{{ exportError.message }}<small v-if="exportError.requestId"> · {{ exportError.requestId }}</small></p><p v-if="exportNotice" role="status">{{ exportNotice }}</p>
    <section class="panel master-list">
      <form ref="formRef" novalidate class="list-filters" @submit.prevent="search">
        <label>关键词<input v-model="filters.keyword" maxlength="100" /></label><label>操作账号<input v-model="filters.actorName" maxlength="100" placeholder="完整账号名称" /></label><label>对象编号<input v-model="filters.objectId" maxlength="100" placeholder="详情中的对象编号" /></label><label>动作<UiSelect v-model="filters.action"><option value="">全部动作</option><option v-for="(label, value) in AUDIT_ACTIONS" :key="value" :value="value">{{ label }}</option></UiSelect></label>
        <label>结果<UiSelect v-model="filters.result"><option value="">全部</option><option v-for="(label, value) in AUDIT_RESULTS" :key="value" :value="value">{{ label }}</option></UiSelect></label><label>开始日期（UTC）<UiDatePicker v-model="filters.dateFrom" type="date" /></label><label data-field="dateTo">结束日期（UTC）<div class="field-control"><UiDatePicker v-model="filters.dateTo" type="date" aria-label="结束日期（UTC）" :aria-invalid="!!errors.dateTo" /><small v-if="errors.dateTo" class="field-error" aria-live="polite">{{ errors.dateTo }}</small></div></label><div class="filter-actions"><button class="button primary">查询</button><button class="button" type="button" @click="reset">重置</button>
      </div></form><div class="section-heading"><h2>操作日志列表</h2><button class="button" :disabled="exporting || list.loading.value" @click="download">{{ exporting ? '正在生成…' : '导出全部筛选结果' }}</button></div>
      <div v-table-region class="admin-results"><QueryState :data="list.data.value" :loading="list.loading.value" :error="list.error.value" @retry="load">
        <template v-if="list.data.value?.rows"><div class="device-table-wrap"><table v-table class="admin-table device-table"><caption class="sr-only">当前厂站授权范围内的操作日志</caption><thead><tr><th data-width="210">时间（北京时间）</th><th data-width="240">记录编号</th><th>操作账号</th><th>业务对象</th><th>动作</th><th>结果</th><th>操作</th></tr></thead><tbody><tr v-for="row in list.data.value.rows" :key="row.id"><td>{{ beijingTime(row.occurredAt) }}</td><td>{{ row.id }}</td><td>{{ row.actorName }}</td><td :title="objectLabel(row)">{{ objectLabel(row) }}</td><td>{{ auditActionLabel(row.action) }}</td><td class="status-cell"><span class="badge">{{ AUDIT_RESULTS[row.result] || row.result }}</span></td><td><button class="button" @click="openDetail(row.id)">查看详情</button></td></tr></tbody></table></div><p v-if="!list.data.value.rows.length" class="query-state">当前筛选下暂无操作日志。</p><AdminPagination :total="list.data.value.total" :model-value="pageNum" :page-size="pageSize" :disabled="list.loading.value" @update:model-value="pageNum=$event; load()" @update:page-size="pageSize=$event; search()" /></template>
      </QueryState></div>
    </section>
    <ModalPanel :open="!!selectedId" title="操作日志详情" heading-id="audit-detail-heading" @close="closeDetail">
      <QueryState :data="detail.data.value" :loading="detail.loading.value" :error="detail.error.value" @retry="loadDetail"><template v-if="detail.data.value?.id"><dl class="record-fields"><template v-for="(label, key) in detailFields" :key="key"><dt>{{ label }}</dt><dd>{{ detailValue(key) }}</dd></template></dl><h3>修改内容</h3><div class="device-table-wrap"><table v-table class="admin-table device-table"><thead><tr><th>字段</th><th>变更前</th><th>变更后</th></tr></thead><tbody><tr v-for="item in differencePages.visibleRows.value" :key="item.key"><td>{{ item.key }}</td><td>{{ json(item.before) }}</td><td>{{ json(item.after) }}</td></tr></tbody></table></div><AdminPagination :total="differences.length" :model-value="differencePages.page.value" :page-size="differencePages.pageSize.value" @update:model-value="differencePages.changePage" @update:page-size="differencePages.changePageSize" /><p v-if="!differences.length">没有可展示的修改内容。</p><h3>修改前记录</h3><pre class="audit-snapshot">{{ json(detail.data.value.before) }}</pre><h3>修改后记录</h3><pre class="audit-snapshot">{{ json(detail.data.value.after) }}</pre></template></QueryState>
    </ModalPanel>
  </section>
</template>
<script setup>
import { beijingTime } from '../tablePresentation'
import { computed, reactive, ref, watch, onBeforeUnmount } from 'vue'
import { useFieldErrors } from '@ui-spec/useFieldErrors'
import { getAdminProvider } from '@admin-provider'
import { useAdminStore } from '../store'
import { useQuery } from '../useQuery'
import { useTablePagination } from '../pagination'
import { AUDIT_RESULTS } from '../auditData'
import { AUDIT_ACTIONS, auditActionLabel, auditObjectLabel, loadAuditDeviceNames } from '../auditPresentation'
import QueryState from '../components/QueryState.vue'
import ModalPanel from '../components/ModalPanel.vue'
const store = useAdminStore(), list = useQuery(), detail = useQuery()
const emptyFilters = () => ({ keyword: '', actorName: '', objectId: '', action: '', result: '', dateFrom: '', dateTo: '' })
const filters = reactive(emptyFilters()), applied = ref(emptyFilters()), pageNum = ref(1), pageSize = ref(10), selectedId = ref('')
const { formRef, errors, validate } = useFieldErrors(() => ({ ...filters }))
const exporting = ref(false), exportError = ref(null), exportNotice = ref('')
let exportController, exportVersion = 0
const deviceNames = ref({})
let namesController, namesVersion = 0
const objectLabel = row => auditObjectLabel(row, deviceNames.value[row?.objectId])
const detailFields = { id: '记录编号', siteId: '厂站编号', actorName: '操作账号', objectId: '业务对象', objectCode: '对象编号', action: '动作', actionCode: '动作代码', result: '结果', occurredAt: '时间（北京时间）', source: '来源', requestId: '请求编号', operationId: '操作编号' }
function detailValue(key) {
  const row = detail.data.value
  if (key === 'objectId') return objectLabel(row)
  if (key === 'objectCode') return row.objectId || '未记录'
  if (key === 'action') return auditActionLabel(row.action)
  if (key === 'actionCode') return row.action || '未记录'
  if (key === 'occurredAt') return beijingTime(row.occurredAt)
  if (key === 'result') return AUDIT_RESULTS[row.result] || row.result
  return row[key] || '未记录'
}
watch(() => [list.data.value, store.siteId, store.identity?.id], async ([data, siteId]) => {
  const version = ++namesVersion; namesController?.abort(); namesController = new AbortController(); deviceNames.value = {}
  if (!data?.rows?.length) return
  const names = await loadAuditDeviceNames(data.rows, getAdminProvider(), siteId, namesController.signal)
  if (version === namesVersion) deviceNames.value = names
})
const json = value => value === undefined ? '未记录' : JSON.stringify(value, null, 2)
const differences = computed(() => { const before = detail.data.value?.before || {}, after = detail.data.value?.after || {}; return [...new Set([...Object.keys(before), ...Object.keys(after)])].filter(key => json(before[key]) !== json(after[key])).map(key => ({ key, before: before[key], after: after[key] })) })
function cancelExport() { exportVersion++; exportController?.abort(); exporting.value = false; exportError.value = null; exportNotice.value = '' }
async function load() { await list.run('audit', { ...applied.value, siteId: store.siteId, pageNum: pageNum.value, pageSize: pageSize.value }); const total = list.data.value?.total; if (total != null && pageNum.value > Math.max(1, Math.ceil(total / pageSize.value))) { pageNum.value = Math.max(1, Math.ceil(total / pageSize.value)); load() } }
function search() { if (!validate({ dateTo: filters.dateFrom && filters.dateTo && filters.dateFrom > filters.dateTo && '结束日期不能早于开始日期' })) return; cancelExport(); closeDetail(); applied.value = { ...filters }; pageNum.value = 1; load() }
function reset() { Object.assign(filters, emptyFilters()); search() }
function turn(step) { pageNum.value += step; load() }
function openDetail(id) { selectedId.value = id; loadDetail() }
function loadDetail() { detail.run('auditDetail', { id: selectedId.value, siteId: store.siteId }) }
function closeDetail() { selectedId.value = ''; detail.cancel() }
async function download() {
  cancelExport(); const version = exportVersion, siteId = store.siteId, identity = store.identity?.id
  exportController = new AbortController(); exporting.value = true
  try {
    const result = await getAdminProvider().query('auditExport', { ...applied.value, siteId }, { signal: exportController.signal })
    if (version !== exportVersion || siteId !== store.siteId || identity !== store.identity?.id) return
    if (typeof result.data?.csv !== 'string') throw new Error('当前日志来源未接入，无法导出')
    const url = URL.createObjectURL(new Blob([result.data.csv], { type: 'text/csv;charset=utf-8' })), link = document.createElement('a')
    try { link.href = url; link.download = result.data.filename; document.body.appendChild(link); link.click(); exportNotice.value = `已生成 ${result.data.total} 条操作日志。` } finally { link.remove(); setTimeout(() => URL.revokeObjectURL(url), 1000) }
  } catch (error) { if (version === exportVersion && error.name !== 'AbortError') { exportError.value = error; if (error.code === 401) getAdminProvider().invalidate() } } finally { if (version === exportVersion) exporting.value = false }
}
watch(() => [store.siteId, store.identity?.id], () => { cancelExport(); closeDetail(); Object.assign(filters, emptyFilters()); applied.value = emptyFilters(); pageNum.value = 1; load() }, { immediate: true, flush: 'sync' })
watch(() => store.revision, () => { cancelExport(); closeDetail(); load() }, { flush: 'sync' })
onBeforeUnmount(() => { cancelExport(); namesVersion++; namesController?.abort() })
const differencePages = useTablePagination(differences, selectedId)
</script>
<style scoped>
.audit-snapshot, pre { white-space: pre-wrap; overflow-wrap: anywhere; max-width: 100%; font-size:14px; }
.audit-snapshot { background: var(--canvas, var(--theme-card)); border-radius: 4px; padding: 16px; }
dd { overflow-wrap: anywhere; }
</style>
