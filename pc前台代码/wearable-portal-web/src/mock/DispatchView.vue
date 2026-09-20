<script setup>
import { computed, reactive, ref, watch, onBeforeUnmount } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ElMessageBox } from 'element-plus'
import { useContextStore } from '@/store/context'
import { usePortalQuery } from '@/composables/usePortalQuery'
import { useBusinessRevision } from '@/composables/useBusinessRevision'
import { dispatchQuery } from '@/utils/dispatch-route'
import { eventTime, phaseLabels } from '@/utils/event-contract'
import DataState from '@/components/personnel/DataState.vue'
import VectorMap from '@/components/spatial/VectorMap.vue'
import { positionReason } from '@/utils/spatial-contract'
import { queryDispatch, commandDispatch, useDispatchStore } from './dispatch-runtime'
import { participantLabels, modeLabels } from './dispatch-service'
import { useLocalEditor } from './useLocalEditor'
import './dispatch.scss'
const route = useRoute(), router = useRouter(), context = useContextStore(), store = useDispatchStore()
const expandedTask = ref('')
const selected = ref([]), groupName = ref(''), text = ref(''), mode = ref('VOICE'), keyword = ref(''), previewReason = ref('本阶段不调用系统语音服务；本机离线语音能力未经确认，试听禁用。')
const { user, dirty, open, busy, error, run, clear } = useLocalEditor(() => { selected.value = []; groupName.value = ''; text.value = '' })
const query = computed(() => dispatchQuery(route.query)), siteId = computed(() => query.value.siteId || context.selectedSiteId), sosId = computed(() => String(route.params.eventId || ''))
const allowed = computed(() => user.roles.includes('owner')), authorized = computed(() => !!user.token && context.state === 'READY' && context.data?.sites.some(s => s.siteId === siteId.value))
const result = reactive(usePortalQuery()), active = computed(() => result.data?.active), sos = computed(() => result.data?.sos.find(e => e.eventId === sosId.value))
let selectedContext = ''
function reload() {
  if (!authorized.value) return result.clear()
  context.select(siteId.value)
  return result.run(async signal => ({ data: await queryDispatch({ ...query.value, siteId: siteId.value, ...(sosId.value ? { eventId: sosId.value } : {}) }, signal) }))
}
watch(() => [route.fullPath, authorized.value, user.token], () => { clear(); keyword.value = query.value.keyword || ''; selectedContext = ''; reload() }, { immediate: true })
watch(() => result.data, d => {
  const key = [siteId.value, query.value.personId, query.value.deviceId, query.value.workId, query.value.eventId, sosId.value].join('|')
  if (d && key !== selectedContext) { selected.value = d.suggested.filter(c => c.modes.includes(mode.value)).map(c => c.deviceId); selectedContext = key }
})
useBusinessRevision(['dispatch', 'events', 'people', 'equipment', 'works'], reload)
function changed() { open.value = true; dirty.value = true }
function page(n) { router.push({ path: '/dispatch', query: { ...query.value, siteId: siteId.value, keyword: keyword.value, pageNum: String(n) } }) }
async function execute(action, extra = {}, confirmed = false) {
  if (!allowed.value || busy.value || !result.data) return
  const input = { siteId: siteId.value, expectedVersion: result.data.version, operationId: crypto.randomUUID(), ...extra }
  const token = user.token
  if (action === 'end' && !confirmed) {
    try { await ElMessageBox.confirm('仅结束本地协同，SOS和其他事件不会完成。', '确认结束本地会话', { confirmButtonText: '确认结束', cancelButtonText: '保留会话' }) } catch { return }
    if (user.token !== token || siteId.value !== input.siteId) return
  }
  return run(async signal => {
    const r = await commandDispatch(action, input, signal)
    if (signal.aborted) return
    dirty.value = false; open.value = false
    if (action === 'broadcast') { text.value = ''; expandedTask.value = r.id }
    if (action === 'receipt') expandedTask.value = extra.taskId
    if (action === 'group') groupName.value = ''
    return r
  })
}
async function start() {
  const token = user.token, site = siteId.value
  const input = { deviceIds: [...selected.value], mode: mode.value, eventId: sosId.value || query.value.eventId || null, workId: query.value.workId || null }
  if (store.active) {
    try { await ElMessageBox.confirm('一次只能存在一个活动本地会话。可保留并打开当前会话，或明确结束后再发起新呼叫。', '已有活动本地会话', { confirmButtonText: '结束后新建', cancelButtonText: '打开已有会话', distinguishCancelAndClose: true }) }
    catch (reason) { if (reason === 'cancel') document.getElementById('dispatch-current')?.scrollIntoView({ behavior: 'auto' }); return }
    if (user.token !== token || siteId.value !== site) return
    const current = store.active
    if (current && !await execute('end', { sessionId: current.id }, true)) return
    await reload()
    if (user.token !== token || siteId.value !== site) return
  }
  await execute('start', input)
}
function group(g) { selected.value = [...g.deviceIds]; changed() }
onBeforeUnmount(() => { /* No RTC, media devices or timers are created by this page. */ })
</script>
<template><div class="dispatch-page">
  <header class="dispatch-heading"><div><p class="dispatch-eyebrow">协同联络 · 服务未接入 · 本地工作空间</p><h1>{{ sosId ? 'SOS 紧急详情' : '调度协同' }}</h1><p>没有真实音视频连接、设备指令或外部拨号；状态由本地操作推进，不表示真实接通。</p></div><button class="dispatch-button" :disabled="busy" @click="reload">刷新协同数据</button></header>
  <DataState v-if="!authorized" :state="context.state === 'LOADING' ? 'LOADING' : 'FORBIDDEN'" message="请选择授权厂站后查看协同" />
  <DataState v-else-if="result.state !== 'READY'" :state="result.error?.errorCode === 'NOT_INTEGRATED' ? 'NOT_INTEGRATED' : result.state" :message="result.error?.message" :retry="!!result.error" @retry="reload" />
  <template v-else-if="result.data">
    <p v-if="!allowed" class="dispatch-note">当前身份仅查询；本地会话、广播和回执操作仅负责人可用。</p>
    <section v-if="sosId" class="dispatch-panel dispatch-sos">
      <template v-if="sos"><h2>{{ sos.title }}</h2><p>求助事件 {{ sos.eventId }} · {{ phaseLabels[sos.phase] }} · 来源：{{ sos.deviceReport.category }}</p><p>发生 {{ eventTime(sos.occurredAt) }}；接收 {{ eventTime(sos.receivedAt) }}。历史人员归属未知，不用当前领用人回填。</p><p>联系能力：{{ result.data.suggested[0]?.reason || '联系对象未接入' }}</p><p>关联会话：{{ result.data.sessions.filter(s => s.eventId === sos.eventId).map(s => s.id).join('、') || '尚无会话；报警可独立存在' }}</p>
        <div class="dispatch-actions"><router-link class="dispatch-button" :to="{ path: '/alarms/' + sos.eventId + '/verification', query: { siteId, returnTo: route.fullPath } }">进入事件处置与记录</router-link><router-link v-if="result.data.suggested.some(c => c.modes.includes('VIDEO'))" class="dispatch-button" :to="{ path: '/video/' + sos.deviceId, query: { siteId, returnTo: route.fullPath } }">查看当前本地视频（非事发录像）</router-link><router-link class="dispatch-button" :to="{ path: '/dispatch', query: { siteId } }">返回调度协同</router-link></div>
        <VectorMap v-if="sos.positionSnapshot" :points="[sos.positionSnapshot]" :message="positionReason(sos.positionSnapshot)" /><p v-else>事件位置未知或无权限；不借用设备当前位置。</p><p v-if="sos.positionSnapshot">触发时冻结的本地位置快照 · {{ positionReason(sos.positionSnapshot) }} · 源时间 {{ eventTime(sos.positionSnapshot.sourceTime) }}</p>
      </template><DataState v-else state="EMPTY" message="SOS事件不存在或不可见" />
    </section>
    <p v-if="error" class="dispatch-error" role="alert">{{ error }}</p>
    <div class="dispatch-columns">
      <div class="dispatch-stack"><section class="dispatch-panel"><h2>联系人与设备</h2><p class="dispatch-note">人员名称仅表达当前明确领用关系；不等于历史求助人。电话仅声明，不提供拨号。</p>
        <form class="dispatch-actions" @submit.prevent="page(1)"><label>搜索联系人或设备<input v-model="keyword" maxlength="100" /></label><button class="dispatch-button">查询联系人</button></form>
        <p v-if="result.data.suggested.length">来源对象：{{ result.data.suggested.map(c => c.name).join('、') }}；可用对象已预选，不会自动呼叫。</p>
        <div class="dispatch-contacts"><label v-for="c in result.data.items" :key="c.deviceId" class="dispatch-contact"><input v-model="selected" type="checkbox" :value="c.deviceId" :disabled="!allowed || !c.modes.includes(mode) || busy" @change="changed" /><span><strong>{{ c.name }} · {{ c.personName }}</strong><small>{{ c.deviceCode }} · 通信 {{ c.communication }}（不代表会话状态）</small><small>{{ c.reason }}</small></span></label></div><p v-if="!result.data.items.length">当前筛选没有联系人。</p>
        <AppPagination :current-page="result.data.pageNum" :page-size="result.data.pageSize" :total="result.data.total" @current-change="page" />
        <p>已选择 {{ selected.length }} 个对象（切换筛选后需重新选择）</p><div class="dispatch-actions"><label>联系模式<select v-model="mode" :disabled="busy" @change="selected = []; changed()"><option value="VOICE">平台语音（本地）</option><option value="VIDEO">视频协同（本地）</option><option value="PHONE">电话（声明，未接入）</option></select></label><button class="dispatch-button primary" :disabled="!allowed || busy || !selected.length || mode === 'PHONE' || !!sosId && !sos" @click="start">{{ store.active ? '处理已有本地会话' : '发起本地呼叫' }}</button></div>
        <p v-if="mode === 'PHONE'">号码、厂家协议与电话网关未接入，不拨号、不显示接通。</p>
        <h3>临时协助组</h3><p>仅本次页面内存中的联系人集合，不修改组织班组。</p><div class="dispatch-actions"><label>协助组名称<input v-model="groupName" maxlength="50" :disabled="!allowed || busy" @input="changed" /></label><button class="dispatch-button" :disabled="!allowed || busy || !selected.length" @click="execute('group', { name: groupName, deviceIds: [...selected] })">保存临时协助组</button></div><button v-for="g in result.data.groups" :key="g.id" class="dispatch-button" :disabled="!allowed || busy" @click="group(g)">{{ g.name }} · {{ g.deviceIds.length }} 个对象</button>
      </section>
      <section class="dispatch-panel"><h2>最近会话记录</h2><p v-if="!result.data.sessions.length">尚无本地会话记录。</p><details v-for="s in result.data.sessions" :key="s.id" class="dispatch-record"><summary>{{ modeLabels[s.mode] }} · {{ s.state === 'ACTIVE' ? '活动中' : '已结束' }} · {{ eventTime(s.createdAt) }}</summary><p>{{ s.id }} · 结束 {{ eventTime(s.endedAt) }}</p><p v-for="p in s.participants" :key="p.deviceId">{{ p.name }} · {{ participantLabels[p.state] }}</p><ol><li v-for="(t, i) in s.timeline" :key="i">{{ t.title }} · {{ eventTime(t.time) }}</li></ol></details></section>
      </div>
      <div class="dispatch-stack"><section id="dispatch-current" class="dispatch-panel"><h2>当前本地会话</h2><p v-if="!active">尚无活动会话；不会自动连接。</p><template v-else><p>{{ modeLabels[active.mode] }} · {{ active.kind === 'GROUP' ? '群呼' : '单呼' }}</p><p class="dispatch-session-count" role="status">{{ active.participants.filter(p => p.state === 'CONNECTED').length }} / {{ active.participants.length }} 个对象本地会话就绪</p><p class="dispatch-note">部分接通不等于全部接通；不使用麦克风、摄像头或RTC。</p><article v-for="p in active.participants" :key="p.deviceId" class="dispatch-participant"><strong>{{ p.name }}</strong><span>{{ participantLabels[p.state] }}</span><div class="dispatch-actions"><button v-for="state in (p.state === 'RINGING' ? ['CONNECTED', 'REJECTED', 'TIMED_OUT', 'LEFT'] : p.state === 'CONNECTED' ? ['LEFT'] : [])" :key="state" class="dispatch-button" :disabled="!allowed || busy" @click="execute('participant', { sessionId: active.id, deviceId: p.deviceId, state })">{{ state === 'LEFT' ? '退出本地会话' : participantLabels[state] }}</button></div></article><button class="dispatch-button" :disabled="!allowed || busy" @click="execute('end', { sessionId: active.id })">结束本地会话</button><ol class="dispatch-timeline"><li v-for="(t, i) in active.timeline" :key="i">{{ t.title }}<small>{{ eventTime(t.time) }}</small></li></ol></template></section>
        <section class="dispatch-panel"><h2>独立广播任务</h2><label>广播内容（最多200字）<textarea v-model="text" maxlength="200" rows="3" :disabled="!allowed || busy" @input="changed" /></label><p>{{ [...text].length }} / 200 · 使用左侧已选对象，仅保存本地任务，不发送设备。</p><div class="dispatch-actions"><button class="dispatch-button" disabled>本机试听未开放</button><button class="dispatch-button" :disabled="!allowed || busy || !selected.length" @click="execute('broadcast', { text, deviceIds: [...selected] })">创建本地广播任务</button></div><p class="dispatch-note">{{ previewReason }}</p>
          <details v-for="b in result.data.broadcasts" :key="b.id" class="dispatch-record" :open="expandedTask === b.id"><summary @click.prevent="expandedTask = expandedTask === b.id ? '' : b.id">{{ b.text }} · {{ eventTime(b.createdAt) }}</summary><p>本地回执，未发送设备；不代表已播报。</p><div v-for="r in b.recipients" :key="r.deviceId" class="dispatch-participant">{{ r.name }} · {{ { PENDING: '待本地回执', SUCCESS: '本地成功', FAILED: '本地失败' }[r.state] }} · {{ eventTime(r.time) }}<div v-if="r.state === 'PENDING'" class="dispatch-actions"><button v-for="s in ['SUCCESS', 'FAILED']" :key="s" class="dispatch-button" :disabled="!allowed || busy" @click="execute('receipt', { taskId: b.id, deviceId: r.deviceId, state: s })">{{ s === 'SUCCESS' ? '本地广播成功' : '本地广播失败' }}</button></div></div></details>
        </section>
        <section class="dispatch-panel"><h2>SOS 求助事件</h2><p>由来源或预置面板明确产生；不从通信中断推定求助。</p><DataState v-if="result.data.sosState !== 'AVAILABLE'" :state="result.data.sosState" message="SOS事件来源不可用；未将其解释为没有求助" compact /><p v-else-if="!result.data.sos.length">当前厂站暂无SOS事件。</p><router-link v-for="e in result.data.sos" :key="e.eventId" class="dispatch-sos-link" :to="{ path: '/dispatch/sos/' + e.eventId, query: { siteId } }">{{ e.title }} · {{ phaseLabels[e.phase] }}</router-link></section>
      </div>
    </div>
  </template>
</div></template>
