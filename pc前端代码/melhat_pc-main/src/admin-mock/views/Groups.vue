<template>
  <section>
    <div class="page-heading"><div><span class="eyebrow">管理中心 / 权限协作</span><h1>{{ detail ? '协助组档案' : '常设协助组' }}</h1><p class="muted">人员组织配置，不发起通信；两端数据不自动同步。</p></div><span class="badge">本地暂存</span></div>
    <nav class="workspace-tabs" aria-label="权限协作导航"><router-link v-for="item in WORKSPACES.filter(w => w.group === 'access')" :key="item.path" :to="{ path: item.path, query: { siteId: store.siteId } }" :class="{ active: item.entity === 'groups' }">{{ item.title }}</router-link></nav>
    <p v-if="notice" class="notice" role="status">{{ notice }}</p>
    <template v-if="!detail">
      <section class="panel master-list"><div class="section-heading"><h2>授权范围内的完整协助组</h2><div><button class="button primary" :disabled="!writable || loading || error || data?.availability !== 'AVAILABLE'" @click="edit(null)">新建协助组</button><small v-if="!writable" class="disabled-reason">无协助组维护权限</small></div></div>
        <form class="list-filters" @submit.prevent="search"><label>编号 / 名称<input v-model="keyword" maxlength="100" /></label><label>状态<select v-model="status"><option value="">全部</option><option value="enabled">启用</option><option value="disabled">停用</option></select></label><button class="button primary">查询</button></form>
        <QueryState :data="data" :loading="loading" :error="error" @retry="load"><div v-if="data?.rows?.length" class="table-scroll"><table><thead><tr><th>协助组</th><th>人员数</th><th>状态 / 策略</th><th>操作</th></tr></thead><tbody><tr v-for="g in data.rows" :key="g.id"><td>{{ g.name }}<small>{{ g.code }}</small></td><td>{{ g.memberCount }} 人</td><td>{{ g.enabled ? '启用' : '停用' }} · {{ !g.sos ? '策略待配置' : g.enabled && g.sos.enabled ? '本地配置已启用，未通知' : '通知不生效' }}</td><td><button class="button" @click="inspect(g)">查看档案</button><button class="button" :disabled="!g.writable" @click="edit(g)">编辑</button><small v-if="!g.writable" class="disabled-reason">无完整范围维护权限</small></td></tr></tbody></table></div><p v-else class="query-state">无匹配协助组，不代表所有厂站均无协助组。</p><div class="pagination"><span>共 {{ data?.total || 0 }} 条 · 第 {{ pageNum }} 页</span><label>每页<select :value="pageSize" @change="navigate({ pageSize: $event.target.value, pageNum: '1' })"><option>20</option><option>50</option><option>100</option></select></label><button class="button" :disabled="pageNum <= 1" @click="navigate({ pageNum: String(pageNum - 1) })">上一页</button><button class="button" :disabled="pageNum * pageSize >= data?.total" @click="navigate({ pageNum: String(pageNum + 1) })">下一页</button></div></QueryState>
      </section>
    </template>
    <template v-else>
      <router-link class="button" :to="back">返回协助组列表</router-link>
      <QueryState :data="data" :error="error" :loading="loading" @retry="load"><template v-if="data?.id"><section class="panel master-list"><div class="section-heading"><h2>{{ data.name }}</h2><div class="actions"><button class="button" :disabled="!data.writable" @click="edit(data)">编辑协助组</button><button class="button" :disabled="!data.writable || busy" @click="prepareStatus">{{ data.enabled ? '停用协助组' : '启用协助组' }}</button></div></div><p v-if="!data.writable" class="disabled-reason">无完整范围维护权限</p><dl class="record-fields"><dt>编号 / 版本</dt><dd>{{ data.code }} · v{{ data.version }}</dd><dt>管理区域</dt><dd>{{ data.areaName }}</dd><dt>负责人</dt><dd>{{ memberName(data.leaderId) }}</dd><dt>成员数</dt><dd>{{ data.members.length }} 人（不按终端数统计）</dd><dt>SOS 策略</dt><dd>{{ !data.sos ? '待配置' : data.notificationEffective ? '本地策略启用' : '不生效' }}</dd><dt>接收成员</dt><dd>{{ data.sos?.recipientIds.map(memberName).join('、') || '未选择 / 待配置' }}</dd><dt>备注</dt><dd>{{ data.remark || '未填写' }}</dd></dl><p class="notice">仅保存本地通知策略，未发送 SOS 或其他通知；成员、负责人、接收资格均不授予账号或设备权限。</p></section>
        <section class="panel master-list"><h2>成员与当前终端</h2><QueryState :data="terminals" :error="terminalError" :loading="terminalLoading" @retry="loadTerminals"><article v-for="p in terminals?.rows || []" :key="p.personId" class="binding-card"><h3>{{ p.name }}</h3><p>账号：{{ p.account.state === 'AVAILABLE' ? p.account.name : p.account.state === 'FORBIDDEN' ? '无权查看账号摘要' : '未关联账号' }} · PC / APP：未接入</p><p>{{ Object.entries(p.slots).map(([type, state]) => TYPE_NAMES[type] + '：' + (relationNames[state] || state)).join('；') }}</p><ul><li v-for="d in p.devices" :key="d.id">{{ d.code }} · {{ d.name }} · {{ communicationNames[d.communication] || d.communication }} · {{ d.capability }}</li></ul></article></QueryState></section>
        <section class="panel master-list"><h2>配置历史 · 不可覆盖快照</h2><QueryState :data="history" :error="historyError" :loading="historyLoading" @retry="loadHistory"><article v-for="h in history?.rows || []" :key="h.id" class="binding-card"><h3>v{{ h.version }} · {{ h.name }} · {{ h.enabled ? '启用' : '停用' }}</h3><p>{{ h.occurredAt }} UTC · {{ h.operatorName }} · {{ h.action }}</p><p>成员：{{ h.members.map(p => p.name).join('、') }}</p><p>负责人：{{ h.leader?.name || '待配置' }}；接收人：{{ h.sos?.recipients.map(p => p.name).join('、') || '待配置 / 未选择' }}</p><small>{{ h.source }}</small></article><p v-if="!history?.rows?.length" class="muted">没有配置历史；初始快照不冒充历史办理。</p><div class="pagination"><span>共 {{ history?.total || 0 }} 条</span><button class="button" :disabled="historyPage <= 1" @click="historyPage--; loadHistory()">上一页配置</button><button class="button" :disabled="historyPage * 20 >= history?.total" @click="historyPage++; loadHistory()">下一页配置</button></div></QueryState></section>
      </template></QueryState>
    </template>
    <ModalPanel side :open="editorOpen" title="维护常设协助组" @close="closeEditor"><GroupEditor v-if="editorOpen" :record="editing" :candidates="candidates" :busy="busy" :error="saveError" @dirty="dirty = $event" @save="save" @close="closeEditor" /></ModalPanel>
    <ModalPanel heading-id="group-status-heading" :open="statusOpen" title="协助组启停确认" @close="statusOpen = false"><p>成员与历史保留；停用后策略不生效，重新启用会复核所有关联。</p><p v-if="saveError" class="notice error" role="alert">{{ saveError.message }}</p><button class="button primary" :disabled="busy" @click="setStatus">确认{{ data?.enabled ? '停用' : '启用' }}</button></ModalPanel>
  </section>
</template>
<script setup>
import { computed, ref, watch, onBeforeUnmount } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { getAdminProvider } from '@admin-provider'
import { useAdminStore } from '../store'
import { WORKSPACES, cleanQuery, recordReturn } from '../navigation'
import { TYPE_NAMES } from '../seed'
import ModalPanel from '../components/ModalPanel.vue'
import QueryState from '../components/QueryState.vue'
import GroupEditor from '../components/GroupEditor.vue'
const provider = getAdminProvider(), store = useAdminStore(), route = useRoute(), router = useRouter()
const detail = computed(() => !!route.params.groupId), query = computed(() => cleanQuery(route.query)), pageNum = computed(() => Number(query.value.pageNum || 1)), pageSize = computed(() => Number(query.value.pageSize || 20)), back = computed(() => recordReturn(route.query.returnTo, '/admin/access/groups'))
const writable = computed(() => { void store.revision; return provider.canAny('groups:write', store.siteId) })
const data = ref(null), error = ref(null), loading = ref(false), notice = ref(''), keyword = ref(''), status = ref('')
const terminals = ref(null), terminalError = ref(null), terminalLoading = ref(false), history = ref(null), historyError = ref(null), historyLoading = ref(false), historyPage = ref(1)
const editorOpen = ref(false), editing = ref(null), candidates = ref({ people: [], areas: [] }), dirty = ref(false), busy = ref(false), saveError = ref(null), statusOpen = ref(false)
let controller, terminalController, historyController, saveController, run = 0, terminalRun = 0, historyRun = 0, operationId
const relationNames = { UNASSIGNED: '未领用', ASSIGNED: '已领用', UNKNOWN: '未知', CONFLICT: '关系冲突', FORBIDDEN: '无权查看', UNAVAILABLE: '无权查看装备' }, communicationNames = { ONLINE: '通信在线（不代表可呼叫）', OFFLINE: '离线', UNKNOWN: '通信未知', NOT_CONNECTED: '通信未接入' }
const input = () => ({ siteId: store.siteId, id: route.params.groupId })
function memberName(id) { return data.value?.members?.find(p => p.id === id)?.name || '待配置 / 未知' }
async function load() {
  const id = ++run; controller?.abort(); controller = new AbortController(); loading.value = true; error.value = null
  try { const res = await provider.query(detail.value ? 'group' : 'groups', { ...query.value, ...input(), pageNum: pageNum.value, pageSize: pageSize.value }, { signal: controller.signal }); if (id !== run) return; data.value = res.data; if (!detail.value && data.value.total > 0 && !data.value.rows.length) navigate({ pageNum: String(Math.ceil(data.value.total / pageSize.value)) }); if (detail.value && data.value.id) { loadTerminals(); loadHistory() } }
  catch (e) { if (id === run && e.name !== 'AbortError') { error.value = e; data.value = null; if (e.code === 401) provider.invalidate() } }
  finally { if (id === run) loading.value = false }
}
async function loadTerminals() { const id = ++terminalRun; terminalController?.abort(); terminalController = new AbortController(); terminalLoading.value = true; terminalError.value = null; try { const res = await provider.query('groupTerminals', input(), { signal: terminalController.signal }); if (id === terminalRun) terminals.value = res.data } catch (e) { if (id === terminalRun && e.name !== 'AbortError') terminalError.value = e } finally { if (id === terminalRun) terminalLoading.value = false } }
async function loadHistory() { const id = ++historyRun; historyController?.abort(); historyController = new AbortController(); historyLoading.value = true; historyError.value = null; try { const res = await provider.query('groupHistory', { ...input(), pageNum: historyPage.value }, { signal: historyController.signal }); if (id === historyRun) { history.value = res.data; if (res.data.total > 0 && !res.data.rows.length && historyPage.value > 1) { historyPage.value = Math.ceil(res.data.total / 20); loadHistory() } } } catch (e) { if (id === historyRun && e.name !== 'AbortError') historyError.value = e } finally { if (id === historyRun) historyLoading.value = false } }
function navigate(extra) { return router.replace({ path: '/admin/access/groups', query: { ...query.value, ...extra, siteId: store.siteId, selectedId: undefined } }) }
function search() { navigate({ keyword: keyword.value, status: status.value, pageNum: '1' }) }
function inspect(g) { router.push({ path: `/admin/access/groups/${g.id}`, query: { siteId: store.siteId, returnTo: '/admin/access/groups?' + new URLSearchParams({ ...query.value, siteId: store.siteId, selectedId: g.id }) } }) }
async function getCandidates() { const res = (await provider.query('groupCandidates', { siteId: store.siteId }, { signal: saveController.signal })).data; if (res.availability !== 'AVAILABLE') throw new Error(res.reason || '候选未接入'); return res }
async function edit(row) {
  saveController?.abort(); saveController = new AbortController(); saveError.value = null
  try { const [choices, record] = await Promise.all([getCandidates(), row ? provider.query('group', { siteId: store.siteId, id: row.id }, { signal: saveController.signal }) : null]); if (record && record.data.availability !== 'AVAILABLE') throw new Error('协助组来源未接入'); candidates.value = choices; editing.value = record?.data || null; dirty.value = false; operationId = crypto.randomUUID(); editorOpen.value = true }
  catch (e) { if (e.name !== 'AbortError') notice.value = e.message }
}
function relatedVersions() { return Object.fromEntries([...(editing.value?.members || []), ...candidates.value.areas, ...candidates.value.people].map(p => [p.id, p.version])) }
async function save(form) { await commit(`groups.${editing.value ? 'update' : 'create'}`, { id: editing.value?.id, expectedVersion: editing.value?.version, relatedVersions: relatedVersions(), data: form }) }
async function prepareStatus() { saveController?.abort(); saveController = new AbortController(); saveError.value = null; try { candidates.value = await getCandidates(); operationId = crypto.randomUUID(); statusOpen.value = true } catch (e) { if (e.name !== 'AbortError') notice.value = e.message } }
async function setStatus() { await commit('groups.status', { id: data.value.id, expectedVersion: data.value.version, enabled: !data.value.enabled, relatedVersions: relatedVersions() }) }
async function commit(type, payload) { busy.value = true; saveError.value = null; saveController = new AbortController(); try { await provider.execute(type, { ...payload, siteId: store.siteId, operationId }, { signal: saveController.signal }); dirty.value = false; editorOpen.value = false; statusOpen.value = false; notice.value = '本地配置已保存，未发送任何通知。'; await load() } catch (e) { if (e.name !== 'AbortError') { saveError.value = e; if (e.code === 401) provider.invalidate() } } finally { busy.value = false } }
function allowLeave() { if (busy.value) return false; if (dirty.value && !window.confirm('尚有未保存的协助组修改，确定放弃吗？')) return false; clearForm(); return true }
function closeEditor() { allowLeave() }
function clearForm() { saveController?.abort(); editorOpen.value = false; statusOpen.value = false; dirty.value = false; editing.value = null }
store.leaveGuard = allowLeave
const unsubscribe = provider.subscribe(({ kind }) => { if (['authorization', 'identity', 'expired', 'reset'].includes(kind)) { clearForm(); terminals.value = null; history.value = null; data.value = null; controller?.abort(); terminalController?.abort(); historyController?.abort() } })
watch(() => [route.fullPath, store.siteId, store.revision], () => { keyword.value = query.value.keyword || ''; status.value = query.value.status || ''; load() }, { immediate: true })
watch(() => store.siteId, () => { clearForm(); terminals.value = null; history.value = null; historyPage.value = 1; terminalController?.abort(); historyController?.abort(); terminalRun++; historyRun++ })
const beforeUnload = event => { if (dirty.value) { event.preventDefault(); event.returnValue = '' } }
window.addEventListener('beforeunload', beforeUnload)
onBeforeUnmount(() => { run++; terminalRun++; historyRun++; clearForm(); controller?.abort(); terminalController?.abort(); historyController?.abort(); unsubscribe(); if (store.leaveGuard === allowLeave) store.leaveGuard = null; window.removeEventListener('beforeunload', beforeUnload) })
</script>
