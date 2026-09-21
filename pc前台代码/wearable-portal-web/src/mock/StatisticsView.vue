<script setup>
import { computed, reactive, ref, watch, nextTick, onScopeDispose } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import request from './request.js'
import { useContextStore } from '@/store/context'
import { useUserStore } from '@/store/user'
import { useWorkspaceStore } from '@/store/workspace'
import { usePortalQuery } from '@/composables/usePortalQuery'
import { statisticTabs, statisticsQuery, statisticsCsv } from '@/utils/statistics'
import DataState from '@/components/personnel/DataState.vue'
import StatisticsChart from '@/components/StatisticsChart.vue'
const route = useRoute(), router = useRouter(), context = useContextStore(), user = useUserStore(), workspace = useWorkspaceStore()
const result = reactive(usePortalQuery()), drill = ref(''), page = ref(1), from = ref(''), to = ref(''), formError = ref('')
const q = computed(() => statisticsQuery(route.query)), siteId = computed(() => q.value.siteId || context.selectedSiteId)
const tab = computed(() => q.value.tab || 'comprehensive')
const authorized = computed(() => context.state === 'READY' && context.data?.sites.some(s => s.siteId === siteId.value))
const metrics = computed(() => (result.data?.metrics || []).filter(m => tab.value === 'comprehensive' ? !m.id.startsWith('model-') && !m.id.startsWith('day-') : m.tab === tab.value))
const selected = computed(() => result.data?.metrics.find(m => m.id === drill.value)), rows = computed(() => selected.value?.rows || [])
let dialogNode
function trap(event) {
  if (event.key !== 'Tab') return
  const elements = [...dialogNode.querySelectorAll('button:not(:disabled),a[href],input:not(:disabled),[tabindex="0"]')].filter(el => el.getClientRects().length)
  const index = elements.indexOf(document.activeElement)
  if (index < 0 || event.shiftKey && index === 0 || !event.shiftKey && index === elements.length - 1) {
    event.preventDefault(); elements[event.shiftKey ? elements.length - 1 : 0]?.focus()
  }
}
function cleanDialog() { dialogNode?.removeEventListener('keydown', trap); dialogNode = null }
watch(selected, async value => {
  cleanDialog()
  if (!value) return
  await nextTick()
  dialogNode = document.querySelector('.stats-table')?.closest('.el-dialog')
  dialogNode?.addEventListener('keydown', trap)
  dialogNode?.querySelector('.el-dialog__headerbtn')?.setAttribute('aria-label', '关闭统计明细')
})
watch(page, async () => { await nextTick(); dialogNode?.querySelector('.event-button')?.focus() })
onScopeDispose(cleanDialog)
const labels = { AVAILABLE: '查看同口径明细', FORBIDDEN: '无权限', ERROR: '来源失败', NOT_INTEGRATED: '未接入' }
function reload() {
  drill.value = ''; formError.value = ''
  if (!authorized.value || !user.token) return result.clear()
  context.select(siteId.value)
  result.run(signal => request.get('/api/portal/v1/statistics', { params: { siteId: siteId.value, ...(q.value.from ? { from: q.value.from, to: q.value.to } : {}) }, signal }))
}
watch([siteId, authorized, () => q.value.from, () => q.value.to, () => user.token, () => workspace.revision], reload, { immediate: true })
watch(() => result.data, data => { if (data) { from.value = data.from; to.value = data.to } })
function apply() {
  const next = statisticsQuery({ siteId: siteId.value, tab: tab.value, from: from.value, to: to.value })
  if (!next.from) { formError.value = '请输入完整 UTC 时间（以 Z 结尾），结束时间须大于开始时间。'; return }
  formError.value = ''; router.replace({ path: '/statistics', query: next })
}
function selectTab(value) { drill.value = ''; router.replace({ path: '/statistics', query: { ...q.value, siteId: siteId.value, tab: value } }) }
function open(m) { drill.value = m.id; page.value = 1 }
function exportCsv() {
  if (!selected.value || selected.value.state !== 'AVAILABLE') return
  const blob = new Blob([statisticsCsv(result.data, selected.value)], { type: 'text/csv;charset=utf-8' })
  const url = URL.createObjectURL(blob), a = document.createElement('a')
  a.href = url; a.download = '本地统计明细.csv'; a.click(); setTimeout(() => URL.revokeObjectURL(url), 1000)
}
</script>
<template>
  <section class="statistics">
    <header><div><p class="eyebrow">查询分析 / 同源统计</p><h1>统计分析</h1><p>服务未接入 · 本地工作空间 · 刷新恢复初始数据 · 非正式报表</p></div><button class="event-button" :disabled="!authorized || result.state === 'LOADING'" @click="reload">刷新统计</button></header>
    <nav aria-label="统计视图"><button v-for="(title, key) in statisticTabs" :key="key" :aria-pressed="tab === key" @click="selectTab(key)">{{ title }}</button></nav>
    <form class="stats-filter" @submit.prevent="apply"><label>开始时间 UTC<input v-model="from" placeholder="2026-09-01T00:00:00Z" /></label><label>结束时间 UTC（不含）<input v-model="to" placeholder="2026-10-01T00:00:00Z" /></label><button class="event-button" :disabled="!authorized">应用历史区间</button><p v-if="formError" role="alert">{{ formError }}</p></form>
    <DataState v-if="!authorized" :state="context.state === 'LOADING' ? 'LOADING' : context.state === 'ERROR' ? 'ERROR' : 'NOT_INTEGRATED'" message="请选择授权厂站后查看统计" />
    <DataState v-else-if="result.state !== 'READY'" :state="result.state" :message="result.error?.message" :retry="!!result.error" @retry="reload" />
    <template v-else>
      <StatisticsChart :title="tab === 'events' ? '发生事件按日分布（厂站时区）' : tab === 'tasks' ? '当前监护状态分布' : tab === 'people' ? '当前当班名册' : '当前三类装备分布'" :metrics="result.data.metrics.filter(m => tab === 'people' ? ['duty','rosterUnknown'].includes(m.id) : m.id.startsWith(tab === 'events' ? 'day-' : tab === 'tasks' ? 'work-' : 'type-'))" @select="open" />
      <section class="stats-scope"><strong>{{ result.data.siteName }}</strong><span>日分组：{{ result.data.timeZone }}（缺失时 UTC）</span><span>历史范围：[{{ result.data.from }}, {{ result.data.to }})</span><span>快照读取：{{ result.data.readAt }} · 不是设备上报时间</span></section>
      <p v-if="['comprehensive','equipment'].includes(tab)" class="stats-rate">当前装备领用率 <strong>{{ result.data.assignmentRate === null ? '未知 / 无有效分母' : (result.data.assignmentRate * 100).toFixed(1) + '%' }}</strong> · 分母 {{ result.data.assignmentDenominator ?? '未知' }} 台（已领用 + 明确未领用），未知与冲突不计。</p>
      <section v-for="kind in ['snapshot','history']" :key="kind"><h2>{{ kind === 'snapshot' ? '当前快照' : '历史区间' }}<small>{{ kind === 'snapshot' ? '不随历史区间筛选变化；不可用于推算历史' : '按各项明确时间字段过滤，含起点、不含终点' }}</small></h2><div class="stats-grid"><button v-for="m in metrics.filter(m => m.kind === kind)" :key="m.id" class="stats-metric" :data-metric="m.id" :disabled="m.state !== 'AVAILABLE'" @click="open(m)"><span>{{ m.label }}</span><strong>{{ m.count ?? '—' }}</strong><small>{{ m.note }}</small><span class="stats-action">{{ labels[m.state] }} →</span></button><p v-if="!metrics.some(m => m.kind === kind)" class="stats-none">此视图暂无该口径统计，不推算历史。</p></div></section>
    </template>
    <el-dialog :model-value="!!selected" :title="selected?.label || '统计明细'" width="min(960px, 94vw)" @close="drill = ''"><template v-if="selected"><p>{{ selected.note }}</p><p>共 {{ rows.length }} 条 · 与统计卡完全相同的厂站及口径 · {{ selected.kind === 'snapshot' ? '当前快照' : '历史 [from,to)' }}</p><button class="event-button" @click="exportCsv">导出当前口径 CSV</button><div class="stats-table"><table><thead><tr><th>名称 / 标识</th><th>状态 / 说明</th><th>源时间</th><th>操作</th></tr></thead><tbody><tr v-for="r in rows.slice((page - 1) * 20, page * 20)" :key="r.id"><td>{{ r.name }}<small>{{ r.id }}</small></td><td>{{ r.state }}</td><td>{{ r.time || '未知 / 不适用' }}</td><td><router-link :to="{ path: r.path, query: { siteId, ...(r.path.startsWith('/alarms/') ? { returnTo: route.fullPath } : {}), ...(r.selectedId ? { selectedId: r.selectedId } : {}) } }">查看对象 →</router-link></td></tr></tbody></table></div><p v-if="!rows.length">当前口径没有记录。</p><AppPagination :current-page="page" :page-size="20" :total="rows.length" @current-change="page = $event" /></template></el-dialog>
  </section>
</template>
<style scoped>
.statistics{display:grid;gap:20px;min-width:0;color:var(--text-primary)}header{display:flex;justify-content:space-between;align-items:center;gap:16px}h1{font-size:28px}h2{font-size:19px;margin:0 0 16px}h2 small{margin-left:16px;font-weight:normal}.eyebrow,.stats-action{color:var(--cyan)}header p,small,.stats-scope{color:var(--text-secondary);font-size:13px}nav{display:flex;gap:8px;flex-wrap:wrap}nav button{padding:12px 26px;border:1px solid var(--border);background:var(--panel-bg);color:var(--text-primary)}nav button[aria-pressed=true]{border-color:var(--cyan);color:var(--cyan)}.stats-filter{display:flex;align-items:end;gap:16px;flex-wrap:wrap}.stats-filter label{display:grid;gap:8px;flex:1;min-width:230px}.stats-filter input{width:100%;padding:12px;background:var(--input-bg);color:var(--text-primary);border:1px solid var(--border)}.stats-filter p{width:100%;color:#ffb3ad}.stats-scope{display:flex;gap:12px 24px;flex-wrap:wrap;padding:16px;border-left:3px solid var(--cyan);background:var(--panel-bg)}.stats-scope span{overflow-wrap:anywhere}.stats-rate{color:var(--text-secondary)}.stats-rate strong{color:var(--cyan)}.stats-grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:16px}.stats-metric{display:grid;gap:12px;text-align:left;padding:20px;color:var(--text-primary);border:1px solid var(--border);background:var(--panel-bg);border-radius:5px;min-width:0;overflow-wrap:anywhere}.stats-metric:hover:not(:disabled){border-color:var(--cyan)}.stats-metric strong{font:600 32px/1.2 Consolas,monospace}.stats-metric small{line-height:1.65}.stats-action{font-size:12px}.stats-table{overflow:auto;max-height:50vh;margin:16px 0}table{width:100%;border-collapse:collapse}td,th{text-align:left;padding:12px;border-bottom:1px solid var(--border);overflow-wrap:anywhere}td small{display:block}td a{color:var(--cyan)}.stats-none{color:var(--text-secondary)}button:focus-visible,a:focus-visible,input:focus-visible{outline:2px solid var(--cyan);outline-offset:3px}@media(max-width:1200px){.stats-grid{grid-template-columns:repeat(3,minmax(0,1fr))}}@media(max-width:850px){.stats-grid{grid-template-columns:repeat(2,minmax(0,1fr))}h2 small{display:block;margin:8px 0}}
</style>
