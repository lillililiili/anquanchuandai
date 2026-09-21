<template>
  <section>
    <div class="page-heading"><div><span class="eyebrow">管理中心 / {{ route.meta.group === 'people' ? '人员组织' : '权限协作' }}</span><h1>{{ route.meta.title }}</h1><p class="muted">{{ guidance[entity] }}</p></div><span class="badge">当前页面办理</span></div>
    <nav class="workspace-tabs" aria-label="功能导航"><router-link v-for="item in WORKSPACES.filter(x => x.group === route.meta.group)" :key="item.path" :class="{ active: item.path === route.path }" :to="{ path: item.path, query: { siteId: store.siteId } }">{{ item.title }}</router-link></nav>
    <p v-if="notice" class="notice" role="status">{{ notice }}</p>
    <section v-if="route.meta.entity === 'organizations'" class="tree-pair">
      <div v-for="key in ['organizations', 'areas']" :key="key" class="panel tree-panel"><div class="section-heading"><h2>{{ key === 'organizations' ? '组织 / 班组树' : '厂站区域树' }}</h2><button class="button" @click="switchTree(key)">管理{{ key === 'organizations' ? '组织' : '区域' }}</button></div>
        <TreeBranch :nodes="trees[key] || []" :selected-id="selected?.id" @select="selectTree(key, $event)" /><p v-if="!trees[key]?.length" class="muted">暂无{{ key === 'organizations' ? '组织' : '区域' }}，可新建首个根节点。</p>
      </div>
    </section>
    <section class="panel master-list">
      <div class="section-heading"><div><h2>{{ ENTITIES[entity].title }}列表</h2><small class="muted">{{ currentSite?.name }} · 授权范围 · 演示数据</small></div><div><button class="button primary" :disabled="!writable || loading || !!loadError || list?.availability !== 'AVAILABLE'" @click="openEditor(null)">新增{{ ENTITIES[entity].title }}</button><small v-if="!writable" class="disabled-reason">{{ writeReason }}</small><small v-else-if="loading || loadError || list?.availability !== 'AVAILABLE'" class="disabled-reason">请先完成资料查询</small></div></div>
      <form class="list-filters" @submit.prevent="search"><label>编号 / 名称关键词<input v-model="keyword" maxlength="100" placeholder="输入关键词" /></label><label>启停状态<select v-model="status"><option value="">全部状态</option><option value="enabled">启用</option><option value="disabled">停用 / 已取消</option></select></label><label v-if="entity === 'people'">组织班组<select v-model="organizationId"><option value="">全部组织</option><option v-for="o in options.organizations" :key="o.id" :value="o.id">{{ o.name }}</option></select></label><label v-if="entity === 'people'">区域<select v-model="areaId"><option value="">全部区域</option><option v-for="a in options.areas" :key="a.id" :value="a.id">{{ a.name }}</option></select></label><button class="button primary" type="submit">查询</button><button class="button" type="button" @click="resetFilters">清除筛选</button></form>
      <QueryState :data="list" :error="loadError" :loading="loading" @retry="load">
        <div v-if="list?.rows?.length" class="table-scroll"><table><thead><tr><th>名称 / 标识</th><th>关联信息</th><th>状态</th><th>版本</th><th>办理与查看</th></tr></thead><tbody>
          <tr v-for="row in list.rows" :key="row.id" :class="{ 'selected-row': selected?.id === row.id }">
            <td><button class="record-name" @click="inspect(row)">{{ row.name }}</button><small>{{ row.code || row.loginName || row.id }}</small></td>
            <td>{{ summary(row) }}<small v-if="entity === 'dutyShifts'">{{ displayTime(row.startsAt) }} 至 {{ displayTime(row.endsAt) }}</small><small v-if="entity === 'people'">{{ row.accountId ? '已关联本地账号' : '无登录账号 · 人员独立存在' }}</small></td>
            <td><span class="badge" :class="{ warning: !row.enabled }">{{ row.enabled ? '启用' : entity === 'dutyShifts' ? '已取消' : '停用' }}</span></td><td>v{{ row.version }}</td>
            <td class="table-actions"><template v-if="entity === 'people'"><AssignmentEntry :person-id="row.id" :disabled="!row.enabled" reason="停用人员不能新领用" /><AssignmentEntry mode="return" :person-id="row.id" /></template><button class="button" @click="inspect(row)">查看</button><button class="button" :disabled="!editable(row)" @click="openEditor(row)">编辑</button><button class="button" :disabled="!editable(row) || (entity === 'dutyShifts' && !row.enabled)" @click="prepareStatus(row)">{{ entity === 'dutyShifts' ? '取消班次' : row.enabled ? '停用' : '启用' }}</button><button v-if="['areas', 'organizations'].includes(entity)" class="button danger" :disabled="!editable(row)" @click="prepareStatus(row, true)">删除</button><small v-if="!editable(row)" class="disabled-reason">{{ row.builtin ? '内置记录受保护' : !writable ? writeReason : '已开始/取消的班次仅可查看' }}</small></td>
          </tr>
        </tbody></table></div>
        <div v-else class="query-state"><strong>无匹配记录</strong><p>可调整筛选，或在有维护权限时新增{{ ENTITIES[entity].title }}。</p></div>
        <div v-if="list?.total !== undefined" class="pagination"><span>共 {{ list.total }} 条 · 第 {{ pageNum }} 页</span><label>每页<select :value="pageSize" @change="setPageSize($event.target.value)"><option>20</option><option>50</option><option>100</option></select></label><button class="button" :disabled="pageNum <= 1" @click="setPage(pageNum - 1)">上一页</button><button class="button" :disabled="pageNum * pageSize >= list.total" @click="setPage(pageNum + 1)">下一页</button></div>
      </QueryState>
    </section>
    <ModalPanel heading-id="auth-preview-heading" :open="!!preview" title="确认授权效果" @close="cancelPreview">
      <AuthorizationPreview v-if="preview" :preview="preview" />
      <p v-if="saveError" role="alert" tabindex="-1" class="notice error">{{ saveError.message }} · {{ saveError.errorCode }}</p>
      <div class="actions"><button class="button" :disabled="busy" @click="cancelPreview">返回修改 / 重新预览</button><button class="button primary" :disabled="busy || !!saveError" @click="commitPending">确认授权生效</button></div>
    </ModalPanel>
    <ModalPanel heading-id="reset-credential-heading" :open="!!resetAccount" title="重置演示登录状态" @close="closeReset">
      <form v-if="resetAccount" @submit.prevent="resetCredential"><p>账号：{{ resetAccount.name }}</p><p class="notice">未修改真实密码，重新选择演示账号可进入；不代表其他浏览器或真实终端已退出。</p><label>重置原因<textarea v-model="resetReason" required maxlength="500" /></label><label class="inline-check"><input v-model="resetConfirmed" type="checkbox" required />确认仅更新演示账号的登录验证信息，不改变人员、装备或维修关系</label><p v-if="saveError" ref="resetErrorBox" tabindex="-1" class="notice error" role="alert">{{ saveError.message }}</p><button class="button primary" :disabled="busy || !resetConfirmed">确认重置演示登录状态</button></form>
    </ModalPanel>
    <ModalPanel side :open="editorOpen" :title="(editing ? '编辑' : '新增') + ENTITIES[entity].title" @close="closeEditor">
      <MasterEditor v-if="editorOpen" :key="editorKey" :entity="entity" :record="editing" :options="editorOptions" :site-id="store.siteId" :timezone="currentSite?.timezone || 'UTC'" :busy="busy" :error="saveError" :is-system="provider.isSystem()" @dirty="dirty = $event" @save="save" @close="closeEditor" />
    </ModalPanel>
    <ModalPanel side heading-id="record-heading" :open="entity !== 'people' && !!selected && !editorOpen && !action" :title="ENTITIES[entity].title + ' · 只读详情'" @close="closeInspect">
      <button v-if="entity === 'accounts' && selected" class="button" :disabled="!editable(selected) || selected.id === store.identity?.id" @click="openReset(selected)">重置演示登录状态</button>
      <template v-if="selected"><h3>{{ selected.name }}</h3><dl class="record-fields"><dt>标识</dt><dd>{{ selected.id }}</dd><dt>状态 / 版本</dt><dd>{{ selected.enabled ? '启用' : '停用' }} · v{{ selected.version }}</dd><dt>关联信息</dt><dd>{{ summary(selected) }}</dd><template v-if="entity === 'accounts'"><dt>关联人员</dt><dd>{{ options.people?.find(p => p.id === selected.personId)?.name || '未关联 / 当前不可见' }}</dd><dt>角色范围</dt><dd v-for="roleId in selected.roleIds" :key="roleId">{{ options.roles?.find(r => r.id === roleId)?.name || roleId }} · {{ selected.roleScopes?.[roleId]?.siteIds?.join('、') || '模板范围' }} · {{ selected.roleScopes?.[roleId]?.areaIds === '*' ? '全厂' : selected.roleScopes?.[roleId]?.areaIds?.join('、') || '模板区域' }}</dd></template><template v-if="entity === 'roles'"><dt>操作与范围</dt><dd v-for="(g, index) in selected.grants" :key="index">{{ g.operations.join('、') }}<p>{{ g.siteIds.join('、') }} · {{ g.areaIds === '*' ? '全部区域' : g.areaIds.join('、') }}</p></dd></template><template v-if="entity === 'dutyShifts'"><dt>班次时间（{{ currentSite?.timezone || 'UTC' }}）</dt><dd>{{ displayTime(selected.startsAt) }} 至 {{ displayTime(selected.endsAt) }}</dd><dt>当时的成员名单</dt><dd>{{ selected.memberSnapshots?.map(p => p.name).join('、') }}</dd></template></dl><p class="notice">仅用于本后台演示，未连接真实认证或设备。</p></template>
    </ModalPanel>
    <ModalPanel heading-id="impact-heading" :open="!!action" title="操作影响确认" @close="closeAction">
      <template v-if="action"><p>将{{ action.remove ? '删除' : action.row.enabled ? entity === 'dutyShifts' ? '取消' : '停用' : '启用' }}：<strong>{{ action.row.name }}</strong></p><p class="notice">不进行级联变更。人员、账号和装备相互独立；影响检查在提交时再次执行。</p><QueryState :data="impactData" :loading="impactLoading" :error="impactError" @retry="loadImpacts"><ul v-if="impactData?.rows?.length"><li v-for="r in impactData.rows" :key="r.label + r.id">{{ r.label }}：{{ r.name }}</li></ul><p v-else>未发现阻止本次操作的活动引用。</p></QueryState><p v-if="saveError" class="notice error" role="alert">{{ saveError.message }} · {{ saveError.errorCode }}</p><div class="actions"><button class="button" :disabled="busy" @click="closeAction">保留记录</button><button class="button danger" :disabled="busy || impactLoading || !!impactError || (action.row.enabled || action.remove) && !!impactData?.rows?.length" @click="confirmAction">{{ busy ? '正在处理…' : '确认操作' }}</button></div></template>
    </ModalPanel>
  </section>
</template>
<script setup>
import { computed, ref, watch, onBeforeUnmount, nextTick } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { getAdminProvider } from '@admin-provider'
import { useAdminStore } from '../store'
import { WORKSPACES, cleanQuery } from '../navigation'
import { ENTITIES } from '../masterData'
import { localTime } from '../time'
import ModalPanel from '../components/ModalPanel.vue'
import QueryState from '../components/QueryState.vue'
import AssignmentEntry from '../components/AssignmentEntry.vue'
import MasterEditor from '../components/MasterEditor.vue'
import TreeBranch from '../components/TreeBranch.vue'
import AuthorizationPreview from '../components/AuthorizationPreview.vue'
const provider = getAdminProvider(), store = useAdminStore(), route = useRoute(), router = useRouter()
const entity = computed(() => route.meta.entity === 'organizations' ? query.value.tree || 'organizations' : route.meta.entity)
const guidance = { people: '人员不等于登录账号。先建立人员档案，再按需关联组织、名册和账号。', organizations: '两棵树分别维护。组织与区域的关联不代表数据授权。', areas: '厂站区域与组织独立；已有引用不可级联删除。', sites: '厂站是范围边界。新建厂站仅向系统管理员开放，不自动授权其他身份。', dutyShifts: '手工维护未来班次及成员；无名册不推断当班人数。', accounts: '本地身份选择，不设置密码；新账号默认无授权。', roles: '操作与范围按同一角色匹配，再取并集；不跨角色拼接权限。' }
const currentSite = computed(() => store.sites.find(s => s.id === store.siteId))
const query = computed(() => cleanQuery(route.query)), pageNum = computed(() => Number(query.value.pageNum || 1)), pageSize = computed(() => Number(query.value.pageSize || 20))
const keyword = ref(query.value.keyword || ''), status = ref(query.value.status || ''), organizationId = ref(query.value.organizationId || ''), areaId = ref(query.value.areaId || '')
const list = ref(null), options = ref({}), trees = ref({}), loading = ref(false), loadError = ref(null), notice = ref(''), selected = ref(null)
const editorOpen = ref(false), editing = ref(null), editorKey = ref(0), editorOptions = ref({}), dirty = ref(false), busy = ref(false), saveError = ref(null)
const action = ref(null), impactLoading = ref(false), impactError = ref(null), impactData = ref(null)
const preview = ref(null), pending = ref(null), resetAccount = ref(null), resetReason = ref(''), resetConfirmed = ref(false)
watch(saveError, async error => { if (error) { await nextTick(); document.querySelector('dialog[open][aria-labelledby="auth-preview-heading"] [role="alert"], dialog[open][aria-labelledby="reset-credential-heading"] [role="alert"]')?.focus() } })
let controller, saveController, impactController, run = 0, operationId
const writable = computed(() => { void store.revision; return ['roles', 'sites'].includes(entity.value) ? provider.isSystem() : provider.canAny(ENTITIES[entity.value].write, store.siteId) })
const writeReason = computed(() => ['roles', 'sites'].includes(entity.value) ? '仅系统管理员可维护' : '当前身份只有查询权限')
function editable(row) { return writable.value && (!row.builtin || entity.value === 'accounts' && row.id !== 'demo-system' && provider.isSystem()) && (entity.value !== 'dutyShifts' || row.enabled && Date.parse(row.startsAt) > Date.now()) }
function displayTime(value) { return localTime(value, currentSite.value?.timezone || 'UTC').replace('T', ' ') || '未知' }
function summary(row) {
  if (entity.value === 'people') return (options.value.organizations?.find(o => o.id === row.organizationId)?.name || '组织未关联/已停用') + ' / ' + (options.value.areas?.find(a => a.id === row.areaId)?.name || '区域未关联/已停用')
  if (entity.value === 'sites') return row.timezone || 'UTC'
  if (entity.value === 'dutyShifts') return `${row.personIds.length} 人 · ${currentSite.value?.timezone || 'UTC'}`
  if (entity.value === 'accounts') return row.roleIds.length ? `${row.roleIds.length} 个角色 · ${row.personId ? '已关联人员' : '无人员关联'}` : '尚未分配授权'
  if (entity.value === 'roles') return row.grants.map(g => `${g.operations.length}项操作 / ${g.siteIds.length}个厂站`).join('；')
  return row.parentId ? '上级：' + (trees.value[entity.value]?.find(r => r.id === row.parentId)?.name || '未知') : '根节点'
}
async function load() {
  if (!ENTITIES[entity.value]) return
  const id = ++run; controller?.abort(); controller = new AbortController(); loading.value = true; loadError.value = null
  const input = { ...query.value, siteId: store.siteId, entity: entity.value, pageNum: pageNum.value, pageSize: pageSize.value }
  try {
    const [res, choices] = await Promise.all([provider.query('master', input, { signal: controller.signal }), provider.query('options', { siteId: store.siteId }, { signal: controller.signal })])
    if (id !== run) return
    list.value = res.data; options.value = choices.data
    if (route.meta.entity === 'organizations') {
      const fetchTree = async key => {
        let rows = [], pageNum = 1, total = 0
        do { const r = await provider.query('master', { entity: key, siteId: store.siteId, pageSize: 100, pageNum }, { signal: controller.signal }); if (r.data.availability !== 'AVAILABLE') return []; rows = rows.concat(r.data.rows); total = r.data.total; pageNum++ } while (rows.length < total)
        return rows
      }
      const values = await Promise.all(['organizations', 'areas'].map(fetchTree))
      if (id !== run) return
      trees.value = { organizations: values[0], areas: values[1] }
    }
    if (list.value.total > 0 && !list.value.rows.length && pageNum.value > 1) { setPage(Math.ceil(list.value.total / pageSize.value)); return }
    selected.value = list.value.rows?.find(r => r.id === query.value.selectedId) || null
    if (query.value.selectedId && !selected.value && list.value.availability === 'AVAILABLE') {
      try { const detail = await provider.query('record', { entity: entity.value, siteId: store.siteId, id: query.value.selectedId }, { signal: controller.signal }); if (id === run) selected.value = detail.data }
      catch (e) { if (id === run && e.name !== 'AbortError') notice.value = '原选中记录不存在或当前不可见，请重新选择。' }
    }
  } catch (e) { if (id === run && e.name !== 'AbortError') { loadError.value = e; if (e.code === 401) provider.invalidate() } }
  finally { if (id === run) loading.value = false }
}
function navigate(extra) { return router.replace({ path: route.path, query: { ...query.value, ...extra, siteId: store.siteId } }) }
function search() { navigate({ keyword: keyword.value, status: status.value, organizationId: organizationId.value || undefined, areaId: areaId.value || undefined, pageNum: '1', selectedId: undefined }) }
function resetFilters() { keyword.value = ''; status.value = ''; organizationId.value = ''; areaId.value = ''; search() }
function setPage(page) { navigate({ pageNum: String(page), selectedId: undefined }) }
function setPageSize(size) { navigate({ pageNum: '1', pageSize: size, selectedId: undefined }) }
function switchTree(key) { selected.value = null; navigate({ tree: key, pageNum: '1', selectedId: undefined }) }
function selectTree(key, row) { selected.value = row; navigate({ tree: key, selectedId: row.id, pageNum: '1' }) }
function inspect(row) {
  if (entity.value === 'people') router.push({ path: `/admin/people/${row.id}`, query: { siteId: store.siteId, returnTo: route.path + '?' + new URLSearchParams({ ...query.value, selectedId: row.id, siteId: store.siteId }).toString() } })
  else { selected.value = row; navigate({ selectedId: row.id }) }
}
function closeInspect() { selected.value = null; navigate({ selectedId: undefined }) }
function allowLeave() { if (busy.value) return false; if ((dirty.value || resetReason.value) && !window.confirm('尚有未保存的修改，确定放弃吗？')) return false; dirty.value = false; editorOpen.value = false; preview.value = null; pending.value = null; resetAccount.value = null; resetReason.value = ''; return true }
store.leaveGuard = allowLeave
function openEditor(row) { editing.value = row ? JSON.parse(JSON.stringify(row)) : null; editorOptions.value = JSON.parse(JSON.stringify(options.value)); editorKey.value++; operationId = crypto.randomUUID(); dirty.value = false; saveError.value = null; selected.value = null; editorOpen.value = true }
function closeEditor() { if (allowLeave()) editorOpen.value = false }
function relatedVersions() { return Object.fromEntries(Object.values(editorOptions.value).filter(Array.isArray).flat().map(r => [r.id, r.version])) }
async function save(data) {
  busy.value = true; saveError.value = null; saveController = new AbortController()
  try {
    const type = `${entity.value}.${editing.value ? 'update' : 'create'}`, command = { siteId: store.siteId, id: editing.value?.id, expectedVersion: editing.value?.version, operationId, relatedVersions: relatedVersions(), data }
    if (editing.value && ['accounts', 'roles'].includes(entity.value) && await preparePreview(type, command)) return
    const result = await provider.execute(type, command, { signal: saveController.signal })
    busy.value = false; dirty.value = false; editorOpen.value = false; notice.value = `已保存${ENTITIES[entity.value].title}“${result.data.name}”（仅当前页面）。`; await load()
  } catch (e) { if (e.name !== 'AbortError') { saveError.value = e; if (e.code === 401) provider.invalidate() } }
  finally { busy.value = false }
}
async function loadImpacts() {
  impactController?.abort(); impactController = new AbortController(); impactLoading.value = true; impactError.value = null; impactData.value = null
  try { impactData.value = (await provider.query('impacts', { siteId: store.siteId, entity: entity.value, id: action.value.row.id, all: action.value.remove }, { signal: impactController.signal })).data }
  catch (e) { if (e.name !== 'AbortError') impactError.value = e }
  finally { impactLoading.value = false }
}
function prepareStatus(row, remove = false) { selected.value = null; action.value = { row, remove }; saveError.value = null; operationId = crypto.randomUUID(); loadImpacts() }
function closeAction() { if (!busy.value) { action.value = null; impactController?.abort() } }
async function confirmAction() {
  busy.value = true; saveError.value = null; saveController = new AbortController()
  try { const { row, remove } = action.value; const type = `${entity.value}.${remove ? 'delete' : 'status'}`, command = { siteId: store.siteId, id: row.id, expectedVersion: row.version, enabled: !row.enabled, operationId }; if (entity.value === 'roles' && await preparePreview(type, command)) return; await provider.execute(type, command, { signal: saveController.signal }); busy.value = false; action.value = null; notice.value = '操作已完成（仅当前页面），相关记录未级联修改。'; await load() }
  catch (e) { if (e.name !== 'AbortError') saveError.value = e }
  finally { busy.value = false }
}
async function preparePreview(type, command) {
  const data = (await provider.query('authorizationPreview', { siteId: store.siteId, type, command }, { signal: saveController.signal })).data
  if (data.availability !== 'AVAILABLE') throw Object.assign(new Error(data.reason || '授权预览未接入'), { errorCode: 'NOT_CONNECTED' })
  if (!data.required) return false
  preview.value = data; pending.value = { type, command }; return true
}
function cancelPreview() { if (!busy.value) { preview.value = null; pending.value = null; saveError.value = null } }
async function commitPending() {
  busy.value = true; saveError.value = null; saveController = new AbortController()
  try { await provider.execute(pending.value.type, JSON.parse(JSON.stringify({ ...pending.value.command, previewId: preview.value.previewId })), { signal: saveController.signal }); dirty.value = false; editorOpen.value = false; action.value = null; preview.value = null; pending.value = null; notice.value = '授权已按预览生效（仅本后台本地）'; await load() }
  catch (e) { if (e.name !== 'AbortError') saveError.value = e }
  finally { busy.value = false }
}
function openReset(row) { resetAccount.value = row; resetReason.value = ''; resetConfirmed.value = false; saveError.value = null; operationId = crypto.randomUUID() }
function closeReset() { if (allowLeave()) resetAccount.value = null }
async function resetCredential() {
  busy.value = true; saveError.value = null; saveController = new AbortController()
  try { await provider.execute('accounts.resetCredential', { siteId: store.siteId, id: resetAccount.value.id, expectedVersion: resetAccount.value.version, operationId, reason: resetReason.value, confirm: resetConfirmed.value }, { signal: saveController.signal }); resetAccount.value = null; resetReason.value = ''; notice.value = '演示账号的登录验证信息已更新，未修改真实密码。'; await load() }
  catch (e) { if (e.name !== 'AbortError') saveError.value = e }
  finally { busy.value = false }
}
const unsubscribe = provider.subscribe(({ kind }) => { if (['identity', 'expired', 'reset', 'authorization'].includes(kind)) { saveController?.abort(); editorOpen.value = false; dirty.value = false; action.value = null; preview.value = null; pending.value = null; resetAccount.value = null; resetReason.value = '' } })
watch(() => [route.fullPath, store.siteId, store.revision, entity.value], () => {
  keyword.value = query.value.keyword || ''; status.value = query.value.status || ''; organizationId.value = query.value.organizationId || ''; areaId.value = query.value.areaId || ''; load()
}, { immediate: true })
watch(() => store.siteId, () => { editorOpen.value = false; dirty.value = false; action.value = null; selected.value = null; saveController?.abort(); impactController?.abort() })
const beforeUnload = event => { if (dirty.value) { event.preventDefault(); event.returnValue = '' } }
window.addEventListener('beforeunload', beforeUnload)
onBeforeUnmount(() => { unsubscribe(); run++; controller?.abort(); saveController?.abort(); impactController?.abort(); if (store.leaveGuard === allowLeave) store.leaveGuard = null; window.removeEventListener('beforeunload', beforeUnload) })
</script>
