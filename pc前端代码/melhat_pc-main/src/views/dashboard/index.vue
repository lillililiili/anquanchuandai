<template>
  <div class="app-container admin-dashboard">
    <section class="site-context" aria-labelledby="dashboard-title">
      <div>
        <p class="site-context__eyebrow">CURRENT SITE / 当前管理范围</p>
        <h1 id="dashboard-title">{{ currentSiteName }}</h1>
        <p>维护人员、资产与作业规则；现场处置请使用安卓端。</p>
      </div>
      <div class="site-context__stamp">
        <span>数据更新</span>
        <strong>{{ refreshedAt || '—' }}</strong>
      </div>
    </section>

    <el-alert v-if="error" title="概览加载失败" :description="error" type="error" show-icon :closable="false">
      <template #default><el-button link type="primary" @click="load">重新加载</el-button></template>
    </el-alert>

    <section v-loading="loading" class="metric-grid" aria-label="管理指标">
      <button v-for="item in metrics" :key="item.key" class="metric-card" type="button" @click="go(item.path)">
        <span class="metric-card__label">{{ item.label }}</span>
        <strong>{{ item.value }}</strong>
        <span class="metric-card__detail">{{ item.detail }}</span>
      </button>
    </section>

    <div class="dashboard-grid">
      <section class="data-panel" aria-labelledby="asset-heading">
        <header><div><p>ASSET HEALTH</p><h2 id="asset-heading">设备资产分布</h2></div><el-button link type="primary" @click="go('/assets/devices')">查看台账</el-button></header>
        <div v-for="item in assetRows" :key="item.key" class="distribution-row">
          <span>{{ item.label }}</span>
          <div class="distribution-track"><i :style="{ width: item.percent + '%' }"></i></div>
          <strong>{{ item.value }}</strong>
        </div>
      </section>

      <section class="data-panel" aria-labelledby="task-heading">
        <header><div><p>WORK CONFIG</p><h2 id="task-heading">作业配置状态</h2></div><el-button link type="primary" @click="go('/work/tasks')">管理任务</el-button></header>
        <div class="status-pairs">
          <div v-for="item in taskRows" :key="item.key"><span>{{ item.label }}</span><strong>{{ item.value }}</strong></div>
        </div>
        <div class="panel-note"><span class="status-dot status-dot--safe"></span>已启用围栏 {{ overview.fences?.enabled || 0 }} 条</div>
      </section>

      <section class="data-panel data-panel--wide" aria-labelledby="trend-heading">
        <header><div><p>SAFETY AUDIT / 7 DAYS</p><h2 id="trend-heading">近 7 日事件记录</h2></div><el-button link type="primary" @click="go('/audit/events')">进入审计</el-button></header>
        <div class="trend-chart" role="img" :aria-label="trendLabel">
          <div v-for="point in trend" :key="point.date" class="trend-column">
            <span>{{ point.count }}</span>
            <i :style="{ height: trendHeight(point.count) }"></i>
            <small>{{ shortDate(point.date) }}</small>
          </div>
        </div>
      </section>

      <section class="data-panel data-panel--wide" aria-labelledby="attention-heading">
        <header><div><p>MAINTENANCE QUEUE</p><h2 id="attention-heading">待维护事项</h2></div><span class="attention-total">共 {{ attentionTotal }} 项</span></header>
        <div class="attention-list">
          <button v-for="item in attentionRows" :key="item.key" type="button" @click="go(item.path)">
            <span>{{ item.label }}</span><strong>{{ item.value }}</strong><small>{{ item.hint }}</small><b aria-hidden="true">查看 →</b>
          </button>
        </div>
      </section>
    </div>

    <section class="shortcut-panel" aria-labelledby="shortcut-heading">
      <div><p>QUICK ENTRY</p><h2 id="shortcut-heading">常用维护入口</h2></div>
      <nav aria-label="常用维护入口">
        <button v-for="item in shortcuts" :key="item.path" type="button" @click="go(item.path)">
          <span>{{ item.label }}</span><small>{{ item.desc }}</small><b aria-hidden="true">→</b>
        </button>
      </nav>
    </section>
  </div>
</template>

<script setup>
import { getAdminOverview } from '@/api/wear/admin'
import useUserStore from '@/store/modules/user'

const router = useRouter()
const userStore = useUserStore()
const loading = ref(false)
const error = ref('')
const refreshedAt = ref('')
const overview = ref({ people: {}, devices: {}, tasks: {}, fences: {}, events: {}, eventTrend: [] })

const currentSiteName = computed(() => {
  const current = userStore.sites.find(item => String(item.id) === String(userStore.currentSiteId))
  return current?.name || (userStore.isPlatformAdmin ? '全平台管理' : '未选择厂站')
})

const metrics = computed(() => [
  { key: 'people', label: '在册人员', value: overview.value.people?.total || 0, detail: `启用 ${overview.value.people?.active || 0} 人`, path: '/master-data/people' },
  { key: 'devices', label: '设备资产', value: overview.value.devices?.total || 0, detail: `已领用 ${overview.value.devices?.issued || 0} 台`, path: '/assets/devices' },
  { key: 'tasks', label: '作业任务', value: overview.value.tasks?.active || 0, detail: `草稿 ${overview.value.tasks?.draft || 0} 项`, path: '/work/tasks' },
  { key: 'fences', label: '围栏规则', value: overview.value.fences?.total || 0, detail: `启用 ${overview.value.fences?.enabled || 0} 条`, path: '/work/fences' },
  { key: 'events', label: '未关闭事件', value: overview.value.events?.open || 0, detail: `7 日新增 ${overview.value.events?.last7Days || 0} 条`, path: '/audit/events' }
])

const assetRows = computed(() => {
  const total = Math.max(Number(overview.value.devices?.total || 0), 1)
  return [
    ['inStock', '在库'], ['issued', '已领用'], ['maintenance', '维修'], ['disabled', '停用/报废']
  ].map(([key, label]) => ({ key, label, value: overview.value.devices?.[key] || 0, percent: Math.round((overview.value.devices?.[key] || 0) / total * 100) }))
})
const taskRows = computed(() => [
  { key: 'draft', label: '草稿', value: overview.value.tasks?.draft || 0 },
  { key: 'ready', label: '待开始', value: overview.value.tasks?.ready || 0 },
  { key: 'progress', label: '进行中', value: overview.value.tasks?.inProgress || 0 },
  { key: 'paused', label: '已暂停', value: overview.value.tasks?.paused || 0 }
])
const attentionRows = computed(() => [
  { key: 'events', label: '未关闭事件', value: overview.value.events?.open || 0, hint: '核对处置时间线与关联对象', path: '/audit/events' },
  { key: 'maintenance', label: '维修中设备', value: overview.value.devices?.maintenance || 0, hint: '检查维修和恢复入库状态', path: '/assets/devices' },
  { key: 'drafts', label: '草稿任务', value: overview.value.tasks?.draft || 0, hint: '补齐成员、时段和关联区域', path: '/work/tasks' },
  { key: 'fences', label: '未启用围栏', value: Math.max(0, Number(overview.value.fences?.total || 0) - Number(overview.value.fences?.enabled || 0)), hint: '检查范围和生效规则', path: '/work/fences' }
])
const attentionTotal = computed(() => attentionRows.value.reduce((sum, item) => sum + Number(item.value || 0), 0))
const trend = computed(() => overview.value.eventTrend || [])
const trendMax = computed(() => Math.max(...trend.value.map(item => Number(item.count || 0)), 1))
const trendLabel = computed(() => `近 7 日共记录 ${overview.value.events?.last7Days || 0} 条事件`)
const shortcuts = [
  { label: '人员台账', desc: '维护人员有效期与归属', path: '/master-data/people' },
  { label: '设备台账', desc: '录入型号和资产编号', path: '/assets/devices' },
  { label: '围栏配置', desc: '绘制区域与生效规则', path: '/work/fences' },
  { label: '作业任务', desc: '安排人员和作业时段', path: '/work/tasks' }
]

function unwrap(res) { return res?.data !== undefined ? res.data : res }
function shortDate(date) { return date ? String(date).slice(5) : '—' }
function trendHeight(count) { return `${Math.max(8, Math.round(Number(count || 0) / trendMax.value * 88))}px` }
function go(path) { router.push(path) }
function load() {
  loading.value = true
  error.value = ''
  getAdminOverview().then(res => {
    overview.value = unwrap(res) || overview.value
    refreshedAt.value = new Date().toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' })
  }).catch(err => { error.value = err?.message || '请检查厂站权限或网络连接。' }).finally(() => { loading.value = false })
}
function onSiteChanged() { load() }
onMounted(() => { load(); window.addEventListener('site-changed', onSiteChanged) })
onUnmounted(() => window.removeEventListener('site-changed', onSiteChanged))
</script>

<style scoped>
.admin-dashboard { display: grid; gap: 14px; }
.site-context { display: flex; align-items: flex-end; justify-content: space-between; min-height: 126px; padding: 22px 24px; color: #fff; border-radius: 8px; background: linear-gradient(112deg, #163252 0%, #1d4f78 63%, #1a6372 100%); box-shadow: 0 10px 24px rgba(23, 65, 101, .16); }
.site-context__eyebrow, .data-panel header p, .shortcut-panel > div p { margin: 0 0 5px; font-size: 11px; font-weight: 700; letter-spacing: .09em; opacity: .72; }
.site-context h1 { margin: 0; font-size: 26px; line-height: 1.25; }.site-context p:last-child { margin: 7px 0 0; color: rgba(255,255,255,.78); font-size: 13px; }
.site-context__stamp { display: grid; gap: 5px; min-width: 132px; padding-left: 18px; border-left: 1px solid rgba(255,255,255,.28); }.site-context__stamp span { font-size: 12px; opacity: .72; }.site-context__stamp strong { font: 650 20px/1.2 ui-monospace, SFMono-Regular, Consolas, monospace; }
.metric-grid { display: grid; grid-template-columns: repeat(5, minmax(150px, 1fr)); gap: 12px; }.metric-card { display: grid; gap: 8px; min-height: 112px; padding: 16px; text-align: left; color: var(--text-primary); border: 1px solid var(--border-color); border-radius: 8px; background: #fff; cursor: pointer; transition: border-color .16s, box-shadow .16s, transform .16s; }.metric-card:hover { border-color: #8bb1dd; box-shadow: 0 8px 20px rgba(23,65,101,.09); transform: translateY(-1px); }.metric-card:focus-visible { outline: 3px solid rgba(23,101,209,.25); outline-offset: 2px; }.metric-card__label { color: var(--text-secondary); font-size: 13px; }.metric-card strong { font: 680 30px/1 ui-monospace, SFMono-Regular, Consolas, monospace; }.metric-card__detail { color: var(--text-muted); font-size: 12px; }
.dashboard-grid { display: grid; grid-template-columns: 1.2fr .8fr; gap: 12px; }.data-panel, .shortcut-panel { padding: 17px 18px; border: 1px solid var(--border-color); border-radius: 8px; background: #fff; }.data-panel--wide { grid-column: 1 / -1; }.data-panel header { display: flex; align-items: center; justify-content: space-between; padding-bottom: 13px; border-bottom: 1px solid var(--border-color); }.data-panel h2, .shortcut-panel h2 { margin: 0; font-size: 16px; }.data-panel header p, .shortcut-panel > div p { color: var(--text-muted); }
.distribution-row { display: grid; grid-template-columns: 68px 1fr 42px; align-items: center; gap: 12px; margin-top: 16px; font-size: 13px; }.distribution-row strong { text-align: right; font-family: ui-monospace, SFMono-Regular, Consolas, monospace; }.distribution-track { height: 7px; overflow: hidden; border-radius: 2px; background: #e9eef4; }.distribution-track i { display: block; height: 100%; border-radius: inherit; background: #2b6dad; }
.status-pairs { display: grid; grid-template-columns: repeat(2, 1fr); gap: 10px; margin-top: 14px; }.status-pairs div { display: flex; align-items: center; justify-content: space-between; padding: 12px; border-radius: 6px; background: #f5f8fb; }.status-pairs span { color: var(--text-secondary); font-size: 13px; }.status-pairs strong { font: 650 18px ui-monospace, SFMono-Regular, Consolas, monospace; }.panel-note { margin-top: 13px; color: var(--text-secondary); font-size: 12px; }.status-dot { display: inline-block; width: 7px; height: 7px; margin-right: 7px; border-radius: 50%; }.status-dot--safe { background: #28724e; }
.trend-chart { display: grid; grid-template-columns: repeat(7, 1fr); align-items: end; gap: 16px; height: 146px; padding: 12px 10px 0; }.trend-column { display: grid; grid-template-rows: 18px 88px 18px; justify-items: center; align-items: end; color: var(--text-muted); font-size: 11px; }.trend-column i { width: min(34px, 54%); min-height: 8px; border-radius: 3px 3px 1px 1px; background: linear-gradient(180deg, #df8a2f, #286ca9); }.trend-column span { color: var(--text-primary); font: 600 11px ui-monospace, SFMono-Regular, Consolas, monospace; }
.attention-total { color: var(--text-secondary); font-size: 12px; }.attention-list { display: grid; grid-template-columns: repeat(4, 1fr); gap: 8px; padding-top: 13px; }.attention-list button { position: relative; display: grid; grid-template-columns: 1fr auto; gap: 5px 12px; padding: 12px; text-align: left; color: var(--text-primary); border: 1px solid var(--border-color); border-radius: 6px; background: #f9fbfd; cursor: pointer; }.attention-list button strong { color: #c95f19; font: 680 20px ui-monospace, SFMono-Regular, Consolas, monospace; }.attention-list button small { grid-column: 1 / -1; color: var(--text-muted); }.attention-list button b { grid-column: 1 / -1; color: var(--brand-primary); font-size: 12px; }
.shortcut-panel { display: grid; grid-template-columns: 180px 1fr; align-items: center; gap: 18px; }.shortcut-panel nav { display: grid; grid-template-columns: repeat(4, 1fr); gap: 8px; }.shortcut-panel button { position: relative; display: grid; gap: 4px; padding: 12px 30px 12px 12px; text-align: left; border: 1px solid var(--border-color); border-radius: 6px; background: #f9fbfd; cursor: pointer; }.shortcut-panel button span { font-weight: 650; }.shortcut-panel button small { color: var(--text-muted); }.shortcut-panel button b { position: absolute; right: 12px; top: 20px; color: var(--brand-primary); }
@media (max-width: 1200px) { .metric-grid { grid-template-columns: repeat(3, 1fr); }.attention-list { grid-template-columns: repeat(2, 1fr); }.shortcut-panel { grid-template-columns: 1fr; }.shortcut-panel nav { grid-template-columns: repeat(2, 1fr); } }
@media (prefers-reduced-motion: reduce) { .metric-card { transition: none; } }
</style>
