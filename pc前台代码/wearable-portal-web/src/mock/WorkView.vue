<script setup>
import ContactEntry from '@contact-entry'
import { computed, reactive, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ElMessage, ElMessageBox } from 'element-plus'
import { useContextStore } from '@/store/context'
import { useWorkspaceStore } from '@/store/workspace'
import { usePortalQuery } from '@/composables/usePortalQuery'
import { useBusinessRevision } from '@/composables/useBusinessRevision'
import { useLocalEditor } from './useLocalEditor'
import { getWorks, getWorkEditor, changeWork } from './work-provider'
import { workQuery, safeWorkReturn, monitorLabels, sourceLabels } from '@/utils/work-route'
import { eventTime } from '@/utils/event-contract'
import { eventLocalToUtc, eventLocalTime } from '@/utils/event-route'
import DataState from '@/components/personnel/DataState.vue'
import WorkDetail from './WorkDetail.vue'
import './spatial-editor.scss'
const route = useRoute(), router = useRouter(), context = useContextStore(), workspace = useWorkspaceStore()
const form = reactive({ keyword: '', areaId: '', state: '', sourceStatus: '', from: '', to: '' }), filterError = ref('')
const editMode = ref('arrange'), edit = ref({}), choices = ref([]), captured = ref(null)
const { user, open, dirty, busy, error, clear, close, run } = useLocalEditor(() => { edit.value = {}; choices.value = []; captured.value = null })
const query = computed(() => workQuery(route.query)), siteId = computed(() => query.value.siteId || context.selectedSiteId)
const workId = computed(() => String(route.params.workId || query.value.selectedId || '')), standalone = computed(() => !!route.params.workId)
const authorized = computed(() => !!user.token && context.state === 'READY' && context.data?.sites.some(s => s.siteId === siteId.value))
const params = computed(() => { const p = { ...query.value, siteId: siteId.value }; delete p.selectedId; return p })
const list = reactive(usePortalQuery()), detail = reactive(usePortalQuery()), writable = computed(() => user.roles.includes('owner'))
function loadDetail() { if (authorized.value && workId.value) detail.run(signal => getWorks({ siteId: siteId.value, workId: workId.value }, signal)); else detail.clear() }
function loadList() {
  if (!authorized.value) { list.clear(); return }
  context.select(siteId.value)
  if (!standalone.value) list.run(signal => getWorks(params.value, signal))
  else list.clear()
}
function reload() { loadList(); loadDetail() }
watch([() => JSON.stringify(params.value), standalone, authorized, () => user.token], loadList, { immediate: true })
watch([workId, siteId, authorized, () => user.token], loadDetail, { immediate: true })
watch(workId, clear)
watch(() => route.fullPath, () => { Object.assign(form, { keyword: '', areaId: '', state: '', sourceStatus: '', from: '', to: '' }, query.value, { from: eventLocalTime(query.value.from, 'UTC'), to: eventLocalTime(query.value.to, 'UTC') }); filterError.value = '' }, { immediate: true })
useBusinessRevision(['works', 'people', 'equipment', 'events', 'materials'], reload)
watch(() => list.data, d => {
  if (standalone.value || d?.state !== 'AVAILABLE') return
  const lastPage = Math.max(1, Math.ceil(d.total / Number(params.value.pageSize || 20)))
  if (Number(params.value.pageNum || 1) > lastPage) { page(lastPage); return }
  if (!workId.value && d.items.length) select(d.items[0].workId)
})
function search(reset = false) {
  try { const q = reset ? { siteId: siteId.value } : { ...form, siteId: siteId.value, from: eventLocalToUtc(form.from, 'UTC'), to: eventLocalToUtc(form.to, 'UTC') }; if (!!q.from !== !!q.to || q.from && Date.parse(q.from) >= Date.parse(q.to)) throw Error('请填写完整且开始早于结束的 UTC 时间范围'); router.push({ path: '/supervision', query: workQuery(q) }); filterError.value = '' } catch (e) { filterError.value = e.message }
}
function page(n) { router.push({ path: '/supervision', query: { ...query.value, siteId: siteId.value, selectedId: undefined, pageNum: String(n) } }) }
function select(id) { router.replace({ path: '/supervision', query: { ...query.value, siteId: siteId.value, selectedId: id } }) }
const returnTo = computed(() => safeWorkReturn(route.query.returnTo))
const detailTarget = computed(() => ({ path: '/supervision/' + workId.value, query: { siteId: siteId.value, returnTo: route.fullPath } }))
async function begin(mode) {
  clear(); open.value = true; editMode.value = mode
  const target = { siteId: siteId.value, workId: workId.value }
  await run(async signal => { const r = await getWorkEditor(target, signal); if (signal.aborted) return; captured.value = { ...target, expectedVersion: r.data.monitoring.version }; choices.value = r.data.people; edit.value = mode === 'arrange' ? { supervisorId: r.data.monitoring.supervisorId || '', personIds: [...r.data.monitoring.personIds] } : { personId: '', result: 'NEEDS_REVIEW', note: '' }; if (mode === 'check') choices.value = choices.value.filter(p => r.data.monitoring.personIds.includes(p.personId)) })
}
async function submit(action) {
  if (busy.value || !detail.data?.monitoring) return
  const input = { ...(open.value ? captured.value : { siteId: siteId.value, workId: workId.value, expectedVersion: detail.data.monitoring.version }), operationId: crypto.randomUUID(), ...(open.value ? JSON.parse(JSON.stringify(edit.value)) : {}) }
  const token = user.token
  if (action === 'finish') {
    input.expectedOpenCount = detail.data.work.openEventCount
    try { await ElMessageBox.confirm(`当前仍有 ${input.expectedOpenCount} 件未处理告警，结束监护不会关闭这些事件，也不代表作业许可或原系统结案。结束后不能重开，确认继续？`, '确认结束本地监护', { confirmButtonText: '确认结束', cancelButtonText: '继续监护', closeOnHashChange: false }) } catch { return }
    if (token !== user.token || input.siteId !== siteId.value || input.workId !== workId.value) return
    input.confirmFinish = true
  }
  await run(async signal => { const r = await changeWork(action, input, signal); if (signal.aborted) return; dirty.value = false; clear(); ElMessage.success({ message: '本地监护操作已保存，刷新恢复种子', grouping: true }); if (!r.data.replayed) workspace.invalidate(r.data.changedEntities) })
}
</script>
<template>
  <div class="work-monitor">
    <header class="work-heading"><div><p class="work-kicker">作业监护 · 服务未接入 · 本地工作空间</p><h1>{{ standalone ? '作业监护详情' : '作业监护' }}</h1><p>来源作业只读 · 本地监护单独推进 · 不代表现场安全许可</p></div><router-link v-if="standalone" class="event-button" :to="returnTo">返回作业列表</router-link><button class="event-button" :disabled="!authorized || busy" @click="reload">刷新监护数据</button></header>
    <DataState v-if="!authorized" :state="context.state === 'LOADING' ? 'LOADING' : context.state === 'ERROR' ? 'ERROR' : siteId ? 'FORBIDDEN' : 'NOT_INTEGRATED'" :message="context.error?.message || (siteId ? '当前厂站不在授权范围' : '请选择授权厂站；未接入时不显示业务人数')" />
    <template v-else>
      <template v-if="!standalone">
        <form class="work-filters" @submit.prevent="search()"><label>作业名称或单号<input v-model="form.keyword" maxlength="100" /></label><label>区域<select v-model="form.areaId" aria-label="作业区域"><option value="">全部区域</option><option v-for="a in list.data?.areas || []" :key="a.areaId" :value="a.areaId">{{ a.name }}</option></select></label><label>来源状态<select v-model="form.sourceStatus" aria-label="来源作业状态"><option value="">全部来源状态</option><option v-for="(name, key) in sourceLabels" :key="key" :value="key">{{ name }}</option></select></label><label>监护状态<select v-model="form.state" aria-label="本地监护状态"><option value="">全部监护状态</option><option v-for="(name, key) in monitorLabels" :key="key" :value="key">{{ name }}</option></select></label><label>时段起（UTC）<input v-model="form.from" type="datetime-local" /></label><label>时段止（UTC）<input v-model="form.to" type="datetime-local" /></label><button class="event-button primary">查询作业</button><button class="event-button" type="button" @click="search(true)">重置筛选</button></form>
        <p v-if="filterError" role="alert">{{ filterError }}</p><p class="work-note">按来源计划时段与查询时间窗重叠筛选，统一使用 UTC；不是实际人员工时。</p>
        <div v-if="list.data?.state === 'AVAILABLE'" class="work-counts"><span v-for="(label, key) in monitorLabels" :key="key">{{ label }} <strong>{{ list.data.counts[key] }}</strong></span><small>同一筛选范围，共 {{ list.data.total }} 项</small></div>
      </template>
      <div class="work-columns" :class="{ standalone, 'has-selection': !!workId }">
        <section v-if="!standalone" class="work-panel">
          <DataState v-if="list.state !== 'READY' || list.data?.state !== 'AVAILABLE'" :state="list.error ? list.state : list.data?.state || list.state" :message="list.error?.message" :retry="!!list.error" @retry="reload" />
          <template v-else><div class="work-table-scroll"><table class="work-table"><thead><tr><th>来源作业 / 区域</th><th>来源时段（UTC）</th><th>人数 / 未处理告警</th><th>本地监护</th></tr></thead><tbody><tr v-for="w in list.data.items" :key="w.workId" :class="{ selected: workId === w.workId }" @click="select(w.workId)"><td><button class="work-select" :aria-pressed="workId === w.workId" @click.stop="select(w.workId)">{{ w.name }}</button><small>{{ w.sourceWorkNo }} · {{ w.area.name }}</small><small>{{ sourceLabels[w.sourceStatus] }}</small></td><td><small>{{ eventTime(w.startsAt) }}</small><small>至 {{ eventTime(w.endsAt) }}</small></td><td>{{ w.participantCount }} 人 / {{ w.openEventCount ?? '未知' }} 件</td><td><span class="work-status" :data-state="w.monitorState">{{ monitorLabels[w.monitorState] }}</span></td></tr></tbody></table></div><DataState v-if="!list.data.items.length" state="EMPTY" message="当前厂站或筛选条件下没有作业" /><AppPagination :current-page="Number(params.pageNum || 1)" :page-size="Number(params.pageSize || 20)" :total="list.data.total" @current-change="page" /></template>
        </section>
        <section v-if="standalone || workId" class="work-panel">
          <DataState v-if="!workId" state="EMPTY" message="选择一项作业查看监护摘要" />
          <DataState v-else-if="detail.state !== 'READY' || detail.data?.state !== 'AVAILABLE'" :state="detail.error ? detail.state : detail.data?.state || detail.state" :message="detail.error?.message" :retry="!!detail.error" @retry="loadDetail" />
          <template v-else>
            <header class="work-heading"><h2>{{ detail.data.work.name }}</h2><span class="work-status" :data-state="detail.data.monitoring.state">{{ monitorLabels[detail.data.monitoring.state] }}</span></header>
            <dl class="work-facts"><dt>来源状态</dt><dd>{{ sourceLabels[detail.data.work.sourceStatus] }}</dd><dt>来源许可</dt><dd>{{ detail.data.work.sourcePermit }}</dd><dt>计划时段</dt><dd>{{ eventTime(detail.data.work.startsAt) }} ～ {{ eventTime(detail.data.work.endsAt) }}</dd><dt>本地监护人</dt><dd>{{ (detail.data.people.state === 'AVAILABLE' ? detail.data.work.localSupervisorName : null) || (detail.data.monitoring.supervisorId ? '已安排；姓名需人员权限' : '尚未安排') }}</dd><dt>参与人数</dt><dd>{{ detail.data.work.participantCount }}（关联名册，不是在线数）</dd><dt>未处理告警</dt><dd>{{ detail.data.events.state === 'AVAILABLE' ? detail.data.work.openEventCount : '无权或暂不可读取' }}</dd></dl>
            <ContactEntry :site-id="siteId" :work-id="workId" /><div class="work-actions"><button class="event-button" :disabled="!writable || busy || detail.data.monitoring.state !== 'PENDING'" @click="begin('arrange')">安排监护人员</button><button class="event-button" :disabled="!writable || busy || !['PENDING', 'PAUSED'].includes(detail.data.monitoring.state)" @click="begin('check')">记录人工检查</button><button class="event-button primary" :disabled="!writable || busy || detail.data.monitoring.state !== 'PENDING'" @click="submit('start')">开始监护</button><button class="event-button" :disabled="!writable || busy || detail.data.monitoring.state !== 'ACTIVE'" @click="submit('pause')">暂停监护</button><button class="event-button" :disabled="!writable || busy || detail.data.monitoring.state !== 'PAUSED'" @click="submit('resume')">恢复监护</button><button class="event-button" :disabled="!writable || busy || !['ACTIVE', 'PAUSED'].includes(detail.data.monitoring.state)" @click="submit('finish')">结束监护</button></div>
            <p class="work-note">{{ !writable ? '当前身份只读，监护操作仅负责人可用。' : detail.data.monitoring.state === 'ENDED' ? '监护已结束，不支持重开；关联事件仍独立处置。' : '开始前须有有效监护人及参与人员；未知、过期报告需核实，人工记录不是许可。人员调整仅待开始可用；检查仅待开始或暂停可记录。' }}</p><p v-if="error && !open" role="alert">{{ error }}</p>
            <router-link v-if="!standalone" class="work-detail-link" :to="detailTarget">进入作业监护详情 →</router-link>
            <WorkDetail v-else :data="detail.data" :site-id="siteId" :return-to="route.fullPath" />
            <section class="work-timeline"><h3>本地监护时间线</h3><p v-if="!detail.data.monitoring.timeline.length">尚无本地操作记录；不伪造开始时间。</p><ol><li v-for="item in detail.data.monitoring.timeline" :key="item.id"><strong>{{ item.title }}</strong><small>{{ eventTime(item.time) }} · {{ item.actorId }}</small></li></ol></section>
          </template>
        </section>
      </div>
    </template>
    <el-dialog :model-value="open" :title="editMode === 'arrange' ? '安排本地监护' : '记录人工检查（非安全许可）'" width="min(720px, 94vw)" :before-close="close" :close-on-click-modal="false" append-to-body><div class="local-editor work-editor">
      <p>仅关联已有来源作业，不修改工作票或来源许可；刷新清空本地操作。</p>
      <template v-if="captured && editMode === 'arrange'"><label>监护人<select v-model="edit.supervisorId" aria-label="监护人" @change="dirty = true"><option value="">尚未安排</option><option v-for="p in choices" :key="p.personId" :value="p.personId">{{ p.name }}</option></select></label><fieldset><legend>参与人员（同厂站）</legend><div class="work-choices"><label v-for="p in choices" :key="p.personId"><input v-model="edit.personIds" type="checkbox" :value="p.personId" @change="dirty = true" />{{ p.name }}</label></div></fieldset></template>
      <template v-else-if="captured"><label>检查对象<select v-model="edit.personId" aria-label="检查对象" @change="dirty = true"><option value="">请选择参与人员</option><option v-for="p in choices" :key="p.personId" :value="p.personId">{{ p.name }}</option></select></label><label>人工记录<select v-model="edit.result" aria-label="人工检查结果" @change="dirty = true"><option value="NEEDS_REVIEW">待进一步核实</option><option value="ACKNOWLEDGED">已人工查看（非许可）</option></select></label><label>检查说明<textarea v-model="edit.note" maxlength="500" rows="4" @input="dirty = true" /></label></template>
      <p v-if="error" role="alert">{{ error }}；版本冲突请重新读取，不自动重试。</p><ContactEntry :site-id="siteId" :work-id="workId" /><div class="work-actions"><button class="event-button primary" :disabled="busy || !captured" @click="submit(editMode)">保存监护设置</button><button class="event-button" :disabled="busy" @click="close">取消编辑</button></div>
    </div></el-dialog>
  </div>
</template>
<style src="./work.scss" lang="scss"></style>
