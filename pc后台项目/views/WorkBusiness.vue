<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { useAdminStore } from '../store'
import { createWorksApi, WORK_STATUSES, workStatus, workEditable } from '../worksApi'
import { createBusinessConfigApi } from '../businessConfigApi'
import { useConfirmation } from '../confirmation'
import { localTime } from '../time'
import ModalPanel from '../components/ModalPanel.vue'
import WorkEditor from '../components/WorkEditor.vue'

const store = useAdminStore(), api = createWorksApi(), configApi = createBusinessConfigApi(), confirm = useConfirmation()
const tab = ref('settings'), config = ref(null), rows = ref([]), total = ref(0), activeCount = ref(0)
const page = ref(1), pageSize = ref(10), filters = ref({ keyword: '', date: '', status: '' }), applied = ref({})
const loading = ref(false), error = ref(''), notice = ref(''), busy = ref(false), configBusy = ref(false)
const editor = ref(false), dirty = ref(false), editRecord = ref(null), options = ref(null), editError = ref(null), editorKey = ref(0)
const detail = ref(null), detailLoading = ref(false)
const isSystem = computed(() => store.identity?.id === 'demo-system')
const enabled = computed(() => config.value?.workBusinessEnabled === true)
const writable = computed(() => isSystem.value && enabled.value)
const formatTime = value => localTime(value, 'Asia/Shanghai').replace('T', ' ') || '—'
const personName = (work, id) => work?.participantNames?.[id] || options.value?.people?.find(p => p.id === id)?.name || '历史人员'
let disposed = false, listRun = 0, readRun = 0, listController, readController, writeController, pollController
function applyConfig(next) {
  if (!next || config.value && Number(next.version) < Number(config.value.version)) return
  config.value = next
}
async function pollConfig() {
  if (disposed || !isSystem.value || configBusy.value || pollController) return
  pollController = new AbortController()
  try {
    const next = await configApi.read(pollController.signal), before = config.value?.version
    if (disposed) return
    applyConfig(next)
    if (before != null && before !== config.value?.version) await load()
  } catch (e) { if (!disposed && e.name !== 'AbortError') error.value = e.message }
  finally { pollController = null }
}
async function load() {
  if (!isSystem.value || !store.siteId) return
  const run = ++listRun; listController?.abort(); listController = new AbortController(); loading.value = true; error.value = ''
  try {
    const result = await api.list({ siteId: store.siteId, ...applied.value, pageNum: page.value, pageSize: pageSize.value }, listController.signal)
    if (run !== listRun || disposed) return
    rows.value = result.rows || []; total.value = result.total || 0; activeCount.value = result.activeCount || 0; applyConfig(result.businessConfig)
    const maxPage = Math.max(1, Math.ceil(total.value / pageSize.value))
    if (page.value > maxPage) { page.value = maxPage; await load() }
  } catch (e) { if (run === listRun && e.name !== 'AbortError') error.value = e.message }
  finally { if (run === listRun) loading.value = false }
}
async function toggleBusiness() {
  if (!config.value || configBusy.value || busy.value || !isSystem.value) return
  configBusy.value = true; error.value = ''; notice.value = ''
  try {
    const summary = await api.list({ pageNum: 1, pageSize: 1 })
    applyConfig(summary.businessConfig); activeCount.value = summary.activeCount || 0
    const next = !enabled.value
    const accepted = await confirm({ title: next ? '开启作业及外部安监业务？' : '关闭作业及外部安监业务？',
      message: next ? 'PC、安卓和大屏将显示作业功能。历史记录恢复显示，有效的进行中作业恢复关联；关闭期间事件不会自动补关联。' : `将对全部厂站生效。目前共有 ${activeCount.value} 项进行中作业。PC、安卓、大屏和导出将移除作业及外部安监信息；后台作业只读。人员装备、设备上报、告警核验和通信继续运行，历史记录保留。`,
      confirmText: next ? '确认开启' : '确认关闭', cancelText: '保持当前状态' })
    if (!accepted || disposed) return
    const saved = await configApi.configure({ workBusinessEnabled: next }, config.value.version)
    if (disposed) return
    applyConfig(saved); notice.value = `已${next ? '开启' : '关闭'}，在线使用端将在刷新业务配置后同步。`
    await load()
  } catch (e) { if (!disposed && e.name !== 'AbortError') error.value = e.message }
  finally { configBusy.value = false }
}
async function closeEditor() {
  if (busy.value || dirty.value && !await confirm({ message: '作业登记尚未保存，放弃后将无法恢复。' })) return false
  dirty.value = false; editor.value = false
  if (store.leaveGuard === leaveGuard) store.leaveGuard = null
  return true
}
const leaveGuard = () => closeEditor()
async function openEditor(record = null) {
  if (!writable.value || busy.value || detailLoading.value) return
  const run = ++readRun; readController?.abort(); readController = new AbortController(); detailLoading.value = true; error.value = ''; notice.value = ''
  try {
    const [choices, current] = await Promise.all([api.options(store.siteId, readController.signal), record ? api.detail(record.id, readController.signal) : null])
    if (disposed || run !== readRun) return
    applyConfig(choices.businessConfig)
    if (!writable.value) throw Error('作业业务已关闭，暂不能登记或编辑')
    options.value = choices; editRecord.value = current; editError.value = null; dirty.value = false; editorKey.value++; editor.value = true; store.leaveGuard = leaveGuard
  } catch (e) { if (run === readRun && e.name !== 'AbortError') error.value = e.message }
  finally { if (run === readRun) detailLoading.value = false }
}
async function save(data) {
  if (!writable.value || busy.value) return
  busy.value = true; editError.value = null; writeController = new AbortController()
  try {
    await api.save(editRecord.value?.id, data, writeController.signal)
    if (disposed) return
    dirty.value = false; editor.value = false; if (store.leaveGuard === leaveGuard) store.leaveGuard = null
    notice.value = '作业登记已保存。'; await load()
  } catch (e) { if (!disposed && e.name !== 'AbortError') { editError.value = e; if (e.code === 409) await pollConfig() } }
  finally { busy.value = false }
}
async function showDetail(record) {
  const run = ++readRun; readController?.abort(); readController = new AbortController(); detailLoading.value = true; error.value = ''
  try { const result = await api.detail(record.id, readController.signal); if (!disposed && run === readRun) detail.value = result }
  catch (e) { if (run === readRun && e.name !== 'AbortError') error.value = e.message }
  finally { if (run === readRun) detailLoading.value = false }
}
async function act(record, action) {
  if (!writable.value || busy.value) return
  const label = { start: '开始作业', finish: '结束作业', cancel: '取消作业' }[action]
  const accepted = await confirm({ title: `${label}？`, message: `${record.name}。${action === 'start' ? '将校验计划时间、人员有效性及作业冲突。' : '保留历史记录，关联告警仍需单独核验。'}`, confirmText: label, cancelText: '返回' })
  if (!accepted || !writable.value || disposed) return
  busy.value = true; error.value = ''; notice.value = ''; writeController = new AbortController()
  try { await api.act(record.id, action, record.version, writeController.signal); if (!disposed) { notice.value = `${label}成功。`; await load() } }
  catch (e) { if (!disposed && e.name !== 'AbortError') { await load(); error.value = e.message } }
  finally { busy.value = false }
}
function search() { applied.value = { ...filters.value }; page.value = 1; load() }
function reset() { filters.value = { keyword: '', date: '', status: '' }; search() }
function changePage(value) { page.value = value; load() }
function changeSize(value) { pageSize.value = value; page.value = 1; load() }
function visible() { if (document.visibilityState === 'visible') pollConfig() }
watch(() => [store.siteId, store.identity?.id], () => {
  ++readRun; readController?.abort(); detail.value = null; detailLoading.value = false; rows.value = []; page.value = 1
  if (!isSystem.value) { config.value = null; ++listRun; listController?.abort(); return }
  load(); pollConfig()
}, { immediate: true })
const timer = typeof window !== 'undefined' ? window.setInterval(() => { if (document.visibilityState !== 'hidden') pollConfig() }, 5000) : null
if (typeof document !== 'undefined') document.addEventListener('visibilitychange', visible)
onBeforeUnmount(() => { disposed = true; ++listRun; ++readRun; listController?.abort(); readController?.abort(); writeController?.abort(); pollController?.abort(); if (timer) clearInterval(timer); if (typeof document !== 'undefined') document.removeEventListener('visibilitychange', visible); if (store.leaveGuard === leaveGuard) store.leaveGuard = null })
</script>

<template>
  <section class="work-business">
    <h1 class="sr-only">作业与外部业务</h1>
    <p v-if="!isSystem" class="notice error" role="alert">仅系统管理员可访问作业登记与全局业务设置。</p>
    <template v-else>
      <nav class="work-tabs" aria-label="作业业务分区"><button class="button" :class="{active:tab==='settings'}" :aria-pressed="tab==='settings'" @click="tab='settings'">业务设置</button><button class="button" :class="{active:tab==='works'}" :aria-pressed="tab==='works'" @click="tab='works'">作业登记</button></nav>
      <p v-if="error" class="notice error" role="alert">{{ error }} <button class="button" :disabled="loading" @click="load(); pollConfig()">重新读取</button></p>
      <p v-if="notice" class="notice" role="status">{{ notice }}</p>
      <section v-if="tab === 'settings'" class="panel work-settings">
        <header><div><h2>作业及外部安监业务</h2><p class="muted">统一控制全部厂站的 PC、安卓、大屏与导出内容。</p></div><span class="badge" :class="{ 'work-mode-enabled': enabled }">{{ config ? enabled ? '已开启' : '已关闭' : '正在读取' }}</span></header>
        <div class="work-mode-control"><div><strong>启用作业及外部安监业务</strong><p>{{ enabled ? '可登记作业，开始后关联人员、装备与告警。' : '按人员、装备、告警和核验独立运行，历史作业仅供后台查阅。' }}</p></div><button class="button" :class="enabled ? '' : 'primary'" :disabled="!config || configBusy || busy" @click="toggleBusiness">{{ configBusy ? '正在处理…' : enabled ? '关闭业务' : '开启业务' }}</button></div>
        <dl class="work-config-meta"><dt>修改人</dt><dd>{{ config?.updatedByName || config?.updatedBy || '系统初始配置' }}</dd><dt>修改时间</dt><dd>{{ formatTime(config?.updatedAt) }}</dd><dt>登记方式</dt><dd>本地手工登记</dd></dl>
        <div class="work-policy-note"><h3>关闭后的业务范围</h3><p>各使用端取消作业票、作业关联和外部安监信息。后台作业登记只读，已有作业和告警不会被自动结束，历史资料保留。</p><p>人员装备管理、设备上报、告警认领与核验、视频、语音、定位和地图继续运行。</p></div>
        <p class="muted">当前支持本地作业登记，尚未连接外部工作票或安监系统。</p>
      </section>
      <section v-else class="panel master-list">
        <div class="work-list-heading"><div><h2>作业登记</h2><p class="muted">本地维护作业安排，人工开始、结束并保留处理记录。</p></div><button class="button primary" :disabled="!writable || detailLoading || busy" @click="openEditor()">新增作业</button></div>
        <p v-if="config && !enabled" class="notice warning">作业业务已关闭，历史登记仅供查阅。开启后可继续办理。</p>
        <form class="list-filters" @submit.prevent="search"><label>作业名称 / 编号<input v-model="filters.keyword" maxlength="100" /></label><label>计划日期<UiDatePicker v-model="filters.date" type="date" /></label><label>作业状态<UiSelect v-model="filters.status"><option value="">全部</option><option v-for="status in WORK_STATUSES" :key="status" :value="status">{{ status }}</option></UiSelect></label><div class="filter-actions"><button class="button primary" :disabled="loading">查询</button><button type="button" class="button" :disabled="loading" @click="reset">重置</button></div></form>
        <p v-if="loading" class="query-state" role="status">正在读取作业登记…</p>
        <div v-table-region class="admin-results"><div class="table-scroll"><table v-table class="admin-table work-table"><caption class="sr-only">本地作业登记。时间按北京时间显示，结束作业后仍需单独核验关联告警。</caption><thead><tr><th>作业名称 / 编号</th><th>计划时段</th><th>地点</th><th>负责人 / 监护人</th><th>人数</th><th>状态</th><th class="table-actions">操作</th></tr></thead><tbody><tr v-for="work in rows" :key="work.id"><td><button class="work-name" @click="showDetail(work)">{{ work.name }}</button><small class="work-subline">{{ work.id }} · {{ work.source === 'LOCAL' ? '本地登记' : '历史记录' }}</small></td><td>{{ formatTime(work.plannedStartAt) }}<small class="work-subline">至 {{ formatTime(work.plannedEndAt) }}</small></td><td>{{ work.area }}</td><td>{{ personName(work, work.leader) }}<small class="work-subline">监护人：{{ personName(work, work.supervisor) }}</small></td><td>{{ work.members?.length || 0 }}</td><td><span class="badge">{{ workStatus(work) }}</span><small v-if="work.overdue" class="work-subline warning">已超计划，待人工结束</small></td><td class="table-actions"><div class="row-actions"><button class="button" :disabled="detailLoading" @click="showDetail(work)">详情</button><template v-if="workEditable(work)"><button class="button" :disabled="!writable || detailLoading || busy" @click="openEditor(work)">编辑</button><button v-if="workStatus(work)==='待开始'" class="button primary" :disabled="!writable || busy" @click="act(work,'start')">开始</button><button v-if="workStatus(work)==='进行中'" class="button" :disabled="!writable || busy" @click="act(work,'finish')">结束</button><button class="button" :disabled="!writable || busy" @click="act(work,'cancel')">取消</button></template></div></td></tr></tbody></table></div></div>
        <p v-if="!loading && !rows.length" class="query-state">{{ enabled ? '暂无符合条件的作业，可调整筛选或新增作业。' : '暂无符合条件的历史作业。' }}</p>
        <AdminPagination :total="total" :model-value="page" :page-size="pageSize" :disabled="loading" @update:model-value="changePage" @update:page-size="changeSize" />
      </section>
      <ModalPanel :open="editor" layout="form" :title="editRecord ? '编辑作业登记' : '新增作业登记'" heading-id="work-editor-heading" @close="closeEditor"><WorkEditor v-if="editor && options" :key="editorKey" :record="editRecord" :options="options" :site-id="store.siteId" :busy="busy" :disabled="!writable" :error="editError" @save="save" @dirty="dirty=$event" @close="closeEditor" /></ModalPanel>
      <ModalPanel :open="!!detail" title="作业登记详情" heading-id="work-detail-heading" @close="detail=null"><template v-if="detail"><h3>{{ detail.name }} <span class="badge">{{ workStatus(detail) }}</span></h3><dl class="work-detail"><dt>作业编号</dt><dd>{{ detail.id }}</dd><dt>登记来源</dt><dd>{{ detail.source === 'LOCAL' ? '本地登记' : '历史记录' }}</dd><dt>地点</dt><dd>{{ detail.area }}</dd><dt>计划时段</dt><dd>{{ formatTime(detail.plannedStartAt) }} 至 {{ formatTime(detail.plannedEndAt) }}</dd><dt>负责人</dt><dd>{{ personName(detail,detail.leader) }}</dd><dt>监护人</dt><dd>{{ personName(detail,detail.supervisor) }}</dd><dt>参加人员</dt><dd>{{ detail.members?.map(id => personName(detail,id)).join('、') || '—' }}</dd><dt>备注</dt><dd>{{ detail.remarks || '—' }}</dd></dl><h3>操作记录</h3><ol class="work-history"><li v-for="(entry,index) in detail.timeline || []" :key="index"><time>{{ formatTime(entry.createdAt || entry.time || entry.at) }}</time><span>{{ entry.actorName || entry.operatorName }} {{ entry.text || entry.action }}</span></li></ol><p v-if="!detail.timeline?.length" class="muted">暂无可展示的历史操作记录。</p></template><template #footer><button class="button" @click="detail=null">关闭</button></template></ModalPanel>
    </template>
  </section>
</template>

<style scoped>
.work-tabs{display:flex;gap:10px;margin:0 0 18px}.work-tabs .active{border-color:#4bb7ef;background:rgba(48,155,220,.2);color:#bceaff}.work-settings{max-width:1100px}.work-settings>header,.work-list-heading{display:flex;align-items:center;justify-content:space-between;gap:20px}.work-settings h2,.work-list-heading h2{margin:0 0 8px}.work-settings p,.work-list-heading p{line-height:1.7}.work-mode-control{display:flex;align-items:center;justify-content:space-between;gap:24px;padding:24px 0;border-block:1px solid rgba(105,163,197,.25);margin:20px 0}.work-mode-control strong{font-size:18px}.work-mode-control p{margin-bottom:0}.work-mode-enabled{color:#7ce4c3}.work-config-meta,.work-detail{display:grid;grid-template-columns:110px 1fr;gap:14px 20px;line-height:1.7}.work-config-meta dd,.work-detail dd{margin:0;overflow-wrap:anywhere}.work-config-meta dt,.work-detail dt{color:#9db3c5}.work-policy-note{border-left:3px solid #4baee8;padding:2px 20px;margin:24px 0}.work-policy-note h3{font-size:16px}.work-table{min-width:1080px}.work-subline{display:block;font-size:12px;margin-top:6px;color:#a4b7c5}.work-subline.warning{color:#efc978}.work-name{border:0;background:none;padding:0;color:#8bd5ff;text-align:left;cursor:pointer;font:inherit}.work-name:hover{text-decoration:underline}.work-history{padding-left:20px}.work-history li{padding:10px 0}.work-history time{display:block;font-size:12px;color:#9db3c5}.work-list-heading{margin-bottom:18px}@media(max-width:760px){.work-mode-control{align-items:flex-start;flex-direction:column}.work-config-meta,.work-detail{grid-template-columns:90px 1fr;gap:10px}.work-settings>header{align-items:flex-start}}
</style>
