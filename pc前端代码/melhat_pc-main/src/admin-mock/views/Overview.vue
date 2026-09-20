<template>
  <section>
    <div class="overview-hero"><div><span class="eyebrow">管理中心 / 管理工作台</span><h1>管理工作台</h1><p>从资产概况进入明细，先核对事实，再办理业务。</p><span class="hero-site"><Location aria-hidden="true" /><strong>{{ store.sites.find(s => s.id === store.siteId)?.name }}</strong> · 当前授权范围</span></div><button class="button" @click="refresh">刷新概况</button><span class="hero-caption">装备示意 · 固定预置基准 2026-09-19 · 非实时设备数据</span></div>
    <QueryState :data="overview.data.value" :error="overview.error.value" :loading="overview.loading.value" @retry="loadOverview">
      <div v-if="overview.data.value?.counts" class="metrics">
        <button v-for="(metric, index) in METRICS.slice(0, 4)" :key="metric.key" class="metric-card" @click="openDetails(metric)"><span class="metric-title"><component :is="metricIcons[index]" aria-hidden="true" />{{ metric.label }}</span><strong>{{ overview.data.value.counts[metric.key] }}<small>{{ metric.key === 'maintenance' ? '单' : '台' }}</small></strong><p>{{ metric.note }}</p><span class="metric-link">查看同口径明细 <span aria-hidden="true">↗</span></span></button>
      </div>
      <div v-if="overview.data.value?.counts" class="attention"><WarningFilled class="attention-icon" aria-hidden="true" /><div><strong>待核实的领用关系</strong><p>缺失不等于未领用；冲突不自动修复。</p></div><button v-for="metric in METRICS.slice(4)" :key="metric.key" class="button" @click="openDetails(metric)">{{ metric.label }} <b>{{ overview.data.value.counts[metric.key] }}</b> 台</button></div>
    </QueryState>
    <div class="overview-grid">
      <section class="panel"><div class="section-heading"><h2>管理工作入口</h2><span class="muted small">按业务链路推进</span></div>
        <div class="entry-list"><router-link v-for="(item, index) in MENU.slice(1)" :key="item.path" :to="{ path: item.path, query: { siteId: store.siteId } }"><span class="entry-stage"><component :is="entryIcons[index]" aria-hidden="true" /><span>{{ item.stage }}</span></span><span><strong>{{ item.title }}</strong><small>{{ item.description }}</small></span><span aria-hidden="true">→</span></router-link></div>
      </section>
      <section class="panel"><div class="section-heading"><h2>最近管理变更</h2><span class="badge">内存本地记录</span></div>
        <QueryState :data="audit.data.value" :error="audit.error.value" :loading="audit.loading.value" @retry="loadAudit">
          <ul v-if="audit.data.value?.rows?.length" class="audit-list"><li v-for="record in audit.data.value.rows" :key="record.id"><strong>{{ record.action }}</strong><p>{{ record.actorName }} · {{ record.occurredAt }}</p></li></ul>
          <div v-else class="empty-records"><img :src="stateArt" class="state-art" alt="" width="115" height="90" loading="lazy" /><h3>暂无管理变更记录</h3><p>资料维护和设备建档后会记录到这里，不预置虚构成功记录。</p><small>本页内存保存，刷新恢复初始数据。</small></div>
        </QueryState>
        <div class="boundary-note"><strong>预置边界</strong><p>本后台与监护前台各自保存内存数据。这里的修改不会自动同步到另一端。</p></div>
      </section>
    </div>
    <ModalPanel side :open="!!selected" :title="selected ? selected.label + ' · 只读明细' : ''" @close="closeDetails">
      <p class="notice">{{ selected?.note }}。预置数据，不代表设备已接入。</p>
      <form class="detail-filter" @submit.prevent="search"><label>编号 / 人员关键词<input v-model="keyword" maxlength="100" placeholder="请输入预置编号或人员" /></label><button class="button primary" type="submit">查询</button><button class="button" type="button" @click="clearSearch">重置筛选</button></form>
      <QueryState :data="details.data.value" :error="details.error.value" :loading="details.loading.value" @retry="loadDetails">
        <div v-if="details.data.value?.rows?.length" class="table-scroll"><table>
          <thead><tr><th>设备 / 标识</th><th>领用关系</th><th>通信与新鲜度</th><th>源时间</th></tr></thead>
          <tbody><tr v-for="row in details.data.value.rows" :key="row.id">
            <td><strong>{{ row.code }}</strong><small>{{ row.name }} · {{ row.id }}</small><small v-if="row.type !== 'HELMET'">公共本地结构 · 厂家协议待确认</small></td>
            <td>{{ relationNames[row.relation] }}<small>{{ row.personName || '人员归属未知 / 无当前领用人' }}</small></td>
            <td>{{ communicationNames[row.communication] }}<small>{{ row.freshness === 'STALE' ? '已过期（预置）' : '新鲜度未知' }}</small></td>
            <td>{{ sourceTime(row.sourceTime) }}</td>
          </tr></tbody>
        </table></div>
        <div v-else class="query-state"><strong>无匹配记录</strong><p>已读取预置数据，该厂站或筛选范围没有记录。</p></div>
        <div v-if="details.data.value?.total !== undefined" class="pagination"><span>共 {{ details.data.value.total }} 条 · 每页20条 · 第 {{ pageNum }} 页</span><button class="button" :disabled="pageNum <= 1" @click="changePage(-1)">上一页</button><button class="button" :disabled="pageNum * 20 >= details.data.value.total" @click="changePage(1)">下一页</button></div>
      </QueryState>
    </ModalPanel>
  </section>
</template>
<script setup>
import { ref, watch } from 'vue'
import { Box, Tickets, User, Tools, Location, WarningFilled, Key, Connection, Document } from '@element-plus/icons-vue'
import stateArt from '../assets/visual/state-empty.webp'
import { useAdminStore } from '../store'
import { useQuery } from '../useQuery'
import { METRICS, MENU } from '../navigation'
import QueryState from '../components/QueryState.vue'
import ModalPanel from '../components/ModalPanel.vue'
const store = useAdminStore(), overview = useQuery(), audit = useQuery(), details = useQuery()
const metricIcons = [Box, Tickets, User, Tools]
const entryIcons = [Box, User, Key, Connection, Document]
const selected = ref(null), pageNum = ref(1), keyword = ref(''), submittedKeyword = ref('')
const relationNames = { ASSIGNED: '已领用', UNASSIGNED: '未领用', UNKNOWN: '关系未知', CONFLICT: '关系冲突' }
const communicationNames = { ONLINE: '本地在线', OFFLINE: '本地离线', UNKNOWN: '通信未知' }
function sourceTime(value) { return value && Number.isFinite(Date.parse(value)) ? new Date(value).toISOString().replace('T', ' ').replace('.000Z', ' UTC') : '未知' }
function loadOverview() { overview.run('overview', { siteId: store.siteId }) }
function loadAudit() { audit.run('audit', { siteId: store.siteId, pageSize: 5 }) }
function loadDetails() { if (selected.value) details.run('details', { siteId: store.siteId, metric: selected.value.key, pageNum: pageNum.value, keyword: submittedKeyword.value }) }
function refresh() { loadOverview(); loadAudit(); loadDetails() }
function openDetails(metric) { selected.value = metric; pageNum.value = 1; keyword.value = ''; submittedKeyword.value = ''; loadDetails() }
function closeDetails() { selected.value = null; details.cancel() }
function search() { submittedKeyword.value = keyword.value; pageNum.value = 1; loadDetails() }
function clearSearch() { keyword.value = ''; search() }
function changePage(delta) { pageNum.value += delta; loadDetails() }
watch(() => store.siteId, () => { closeDetails(); refresh() }, { immediate: true })
watch(() => store.revision, refresh)
</script>
