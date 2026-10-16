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

      <form class="list-filters" @submit.prevent="search"><label>编号 / 名称关键词<input v-model="keyword" maxlength="100" placeholder="输入关键词" /></label><label>启停状态<UiSelect v-model="status"><option value="">全部状态</option><option value="enabled">启用</option><option value="disabled">停用 / 已取消</option></UiSelect></label><label v-if="entity === 'people'">组织班组<UiSelect v-model="organizationId"><option value="">全部组织</option><option v-for="o in options.organizations" :key="o.id" :value="o.id">{{ o.name }}</option></UiSelect></label><label v-if="entity === 'people'">区域<UiSelect v-model="areaId"><option value="">全部区域</option><option v-for="a in options.areas" :key="a.id" :value="a.id">{{ a.name }}</option></UiSelect></label><div class="filter-actions"><button class="button primary" type="submit">查询</button><button class="button" type="button" @click="resetFilters">重置</button></div></form><div class="section-heading"><div><h2>{{ ENTITIES[entity].title }}列表</h2><small class="muted">{{ currentSite?.name }} · 授权范围</small></div><div><button class="button primary" :disabled="!writable || loading || !!loadError || list?.availability !== 'AVAILABLE'" @click="openEditor(null)">新增{{ ENTITIES[entity].title }}</button><small v-if="!writable" class="disabled-reason">{{ writeReason }}</small><small v-else-if="loading || loadError || list?.availability !== 'AVAILABLE'" class="disabled-reason">请先完成资料查询</small></div></div>
      <div v-table-region class="admin-results"><QueryState :data="list" :error="loadError" :loading="loading" @retry="load">
        <div v-if="list?.rows?.length" class="table-scroll"><table v-table class="admin-table "><thead><tr><th data-width="180" class="pinned-key">名称</th><th data-width="180">{{ entity === 'accounts' ? '登录名' : '编号 / 标识' }}</th><th v-for="column in tableColumns" :key="column.key" :data-width="column.width || 180" :class="column.numeric ? 'number-cell' : ''">{{ column.label }}</th><th data-width="100" class="status-cell">状态</th><th data-width="80" class="number-cell">版本</th><th data-width="220" class="table-actions pinned-actions">操作</th></tr></thead><tbody><tr v-for="row in list.rows" :key="row.id" :class="{ 'selected-row': selected?.id === row.id }"><td class="pinned-key"><button class="record-name" @click="inspect(row)">{{ row.name }}</button></td><td>{{ row.code || row.loginName || row.id }}</td><td v-for="column in tableColumns" :key="column.key" :class="column.numeric ? 'number-cell' : ''">{{ column.value(row) }}</td><td class="status-cell"><span class="badge" :class="{ warning: !row.enabled }">{{ row.enabled ? '启用' : entity === 'dutyShifts' ? '已取消' : '停用' }}</span></td><td class="number-cell">{{ row.version }}</td><td class="table-actions pinned-actions"><div class="row-actions"><button class="button" @click="inspect(row)">查看</button><button class="button" :disabled="!editable(row)" @click="openEditor(row)">编辑</button><RowMore><template v-if="entity === 'people'"><AssignmentEntry :person-id="row.id" :disabled="!row.enabled" reason="停用人员不能新领用" /><AssignmentEntry mode="return" :person-id="row.id" /></template><button class="button" :disabled="!editable(row) || (entity === 'dutyShifts' && !row.enabled)" @click="prepareStatus(row)">{{ entity === 'dutyShifts' ? '取消班次' : row.enabled ? '停用' : '启用' }}</button><button v-if="['areas', 'organizations'].includes(entity)" class="button danger" :disabled="!editable(row)" @click="prepareStatus(row, true)">删除</button><small v-if="!editable(row)" class="disabled-reason">{{ row.builtin ? '内置记录受保护' : !writable ? writeReason : '已开始/取消的班次仅可查看' }}</small></RowMore></div></td></tr></tbody></table></div>
        <div v-else class="query-state"><strong>无匹配记录</strong><p>可调整筛选，或在有维护权限时新增{{ ENTITIES[entity].title }}。</p></div>
        <AdminPagination v-if="list?.total !== undefined" :total="list.total" :model-value="pageNum" :page-size="pageSize" :disabled="loading" @update:model-value="setPage" @update:page-size="setPageSize(String($event))" />
      </QueryState></div>
    </section>
    <ModalPanel size="wide" heading-id="auth-preview-heading" :open="!!preview" title="确认授权效果" @close="cancelPreview">
      <AuthorizationPreview v-if="preview" :preview="preview" />
      <p v-if="saveError" role="alert" tabindex="-1" class="notice error">{{ saveError.message }} · {{ saveError.errorCode }}</p>
      <template #footer><button class="button" :disabled="busy" @click="cancelPreview">返回修改 / 重新预览</button><button class="button primary" :disabled="busy || !!saveError" @click="commitPending">确认授权生效</button></template>
    </ModalPanel>
    <ModalPanel size="compact" layout="form" heading-id="reset-credential-heading" :open="!!resetAccount" title="重置登录密码" @close="closeReset">
      <form v-if="resetAccount" ref="resetFormRef" class="master-form dialog-form" novalidate @submit.prevent="resetCredential">
        <div class="dialog-form-body"><p>账号：{{ resetAccount.name }}</p><p class="notice">设置新密码后，该账号的PC和安卓已有会话将失效，须使用新密码登录。</p>
        <label>新登录密码<div class="field-control"><input id="reset-password" v-model="resetPassword" type="password" autocomplete="new-password" required minlength="8" maxlength="72" :aria-invalid="!!resetErrors.password" :aria-describedby="resetErrors.password ? 'reset-error-password' : undefined" /><small v-if="resetErrors.password" id="reset-error-password" class="error" aria-live="polite">{{ resetErrors.password }}</small></div></label>
        <label>重置原因<div class="field-control"><textarea id="reset-reason" v-model="resetReason" required maxlength="500" :aria-invalid="!!resetErrors.reason" :aria-describedby="resetErrors.reason ? 'reset-error-reason' : undefined" /><small v-if="resetErrors.reason" id="reset-error-reason" class="error" aria-live="polite">{{ resetErrors.reason }}</small></div></label>
        <div class="field-control"><label class="inline-check"><input id="reset-confirm" v-model="resetConfirmed" type="checkbox" required :aria-invalid="!!resetErrors.confirm" :aria-describedby="resetErrors.confirm ? 'reset-error-confirm' : undefined" />确认重置密码并使已有会话失效，保留人员和装备绑定关系</label><small v-if="resetErrors.confirm" id="reset-error-confirm" class="error" aria-live="polite">{{ resetErrors.confirm }}</small></div>
        <p v-if="resetFormError" data-form-error tabindex="-1" class="error" role="alert">{{ resetFormError }}</p></div><div class="dialog-form-footer"><button type="button" class="button" :disabled="busy" @click="closeReset">取消</button><button class="button primary" :disabled="busy">确认重置登录密码</button></div>
      </form>
    </ModalPanel>
    <ModalPanel layout="form" :size="['areas', 'accounts', 'roles', 'dutyShifts'].includes(entity) ? 'wide' : 'regular'" :open="editorOpen" :title="(editing ? '编辑' : '新增') + ENTITIES[entity].title" @close="closeEditor">
      <MasterEditor v-if="editorOpen" :key="editorKey" :entity="entity" :record="editing" :options="editorOptions" :site-id="store.siteId" :timezone="currentSite?.timezone || 'UTC'" :busy="busy" :error="saveError" :is-system="provider.isSystem()" @dirty="dirty = $event" @save="save" @close="closeEditor" />
    </ModalPanel>
    <ModalPanel heading-id="record-heading" :open="entity !== 'people' && !!selected && !editorOpen && !action" :title="ENTITIES[entity].title + ' · 只读详情'" @close="closeInspect">
      <button v-if="entity === 'accounts' && selected" class="button" :disabled="!editable(selected) || selected.id === store.identity?.id" @click="openReset(selected)">重置登录密码</button>
      <template v-if="selected"><h3>{{ selected.name }}</h3><dl class="record-fields"><dt>标识</dt><dd>{{ selected.id }}</dd><dt>状态 / 版本</dt><dd>{{ selected.enabled ? '启用' : '停用' }} · v{{ selected.version }}</dd><dt>关联信息</dt><dd>{{ summary(selected) }}</dd><template v-if="entity === 'accounts'"><dt>关联人员</dt><dd>{{ options.people?.find(p => p.id === selected.personId)?.name || '未关联 / 当前不可见' }}</dd><dt>角色范围</dt><dd v-for="roleId in selected.roleIds" :key="roleId">{{ options.roles?.find(r => r.id === roleId)?.name || roleId }} · {{ selected.roleScopes?.[roleId]?.siteIds?.join('、') || '模板范围' }} · {{ selected.roleScopes?.[roleId]?.areaIds === '*' ? '全厂' : selected.roleScopes?.[roleId]?.areaIds?.join('、') || '模板区域' }}</dd></template><template v-if="entity === 'roles'"><dt>操作与范围</dt><dd v-for="(g, index) in selected.grants" :key="index">{{ g.operations.join('、') }}<p>{{ g.siteIds.join('、') }} · {{ g.areaIds === '*' ? '全部区域' : g.areaIds.join('、') }}</p></dd></template><template v-if="entity === 'dutyShifts'"><dt>班次时间（{{ currentSite?.timezone || 'UTC' }}）</dt><dd>{{ displayTime(selected.startsAt) }} 至 {{ displayTime(selected.endsAt) }}</dd><dt>当时的成员名单</dt><dd>{{ selected.memberSnapshots?.map(p => p.name).join('、') }}</dd></template></dl><p class="notice">未连接真实认证或设备。</p></template>
    </ModalPanel>
    <ModalPanel size="confirm" heading-id="impact-heading" :open="!!action" title="操作影响确认" @close="closeAction">
      <template v-if="action"><p>将{{ action.remove ? '删除' : action.row.enabled ? entity === 'dutyShifts' ? '取消' : '停用' : '启用' }}：<strong>{{ action.row.name }}</strong></p><p class="notice">不进行级联变更。人员、账号和装备相互独立；影响检查在提交时再次执行。</p><QueryState :data="impactData" :loading="impactLoading" :error="impactError" @retry="loadImpacts"><ul v-if="impactData?.rows?.length"><li v-for="r in impactData.rows" :key="r.label + r.id">{{ r.label }}：{{ r.name }}</li></ul><p v-else>未发现阻止本次操作的活动引用。</p></QueryState><p v-if="saveError" class="notice error" role="alert">{{ saveError.message }} · {{ saveError.errorCode }}</p></template><template v-if="action" #footer><button class="button" :disabled="busy" @click="closeAction">保留记录</button><button class="button danger" :disabled="busy || impactLoading || !!impactError || (action.row.enabled || action.remove) && !!impactData?.rows?.length" @click="confirmAction">{{ busy ? '正在处理…' : '确认操作' }}</button></template>
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
import { masterColumns } from '../masterColumns'
import { localTime } from '../time'
import ModalPanel from '../components/ModalPanel.vue'
import { useConfirmation } from '../confirmation'
import { useFormFeedback } from '../formFeedback'
const confirmDiscard = useConfirmation()
import QueryState from '../components/QueryState.vue'
import AssignmentEntry from '../components/AssignmentEntry.vue'
import MasterEditor from '../components/MasterEditor.vue'
import TreeBranch from '../components/TreeBranch.vue'
import AuthorizationPreview from '../components/AuthorizationPreview.vue'
const provider = getAdminProvider(), store = useAdminStore(), route = useRoute(), router = useRouter()
const entity = computed(() => route.meta.entity === 'organizations' ? query.value.tree || 'organizations' : route.meta.entity)
const guidance = { people: '人员不等于登录账号。先建立人员档案，再按需关联组织、名册和账号。', organizations: '两棵树分别维护。组织与区域的关联不代表数据授权。', areas: '厂站区域与组织独立；已有引用不可级联删除。', sites: '厂站是范围边界。新建厂站仅向系统管理员开放，不自动授权其他身份。', dutyShifts: '手工维护未来班次及成员；无名册不推断当班人数。', accounts: '维护统一登录账号和密码；普通用户关联人员后分配本人业务角色，新账号默认无授权。', roles: '操作与范围按同一角色匹配，再取并集；不跨角色拼接权限。' }
const currentSite = computed(() => store.sites.find(s => s.id === store.siteId))
const query = computed(() => cleanQuery(route.query)), pageNum = computed(() => Number(query.value.pageNum || 1)), pageSize = computed(() => Number(query.value.pageSize || 10))
const keyword = ref(query.value.keyword || ''), status = ref(query.value.status || ''), organizationId = ref(query.value.organizationId || ''), areaId = ref(query.value.areaId || '')
const list = ref(null), options = ref({}), trees = ref({}), loading = ref(false), loadError = ref(null), notice = ref(''), selected = ref(null)
const editorOpen = ref(false), editing = ref(null), editorKey = ref(0), editorOptions = ref({}), dirty = ref(false), busy = ref(false), saveError = ref(null)
const action = ref(null), impactLoading = ref(false), impactError = ref(null), impactData = ref(null)
const preview = ref(null), pending = ref(null), resetAccount = ref(null), resetReason = ref(''), resetPassword = ref(''), resetConfirmed = ref(false)
const resetForm = computed(() => ({ password: resetPassword.value, reason: resetReason.value, confirm: resetConfirmed.value }))
const { formRef: resetFormRef, localErrors: resetLocalErrors, errors: resetErrors, formError: resetFormError, focusErrors: focusResetErrors } = useFormFeedback(resetForm, () => resetAccount.value ? saveError.value : null, 'reset-')
watch(saveError, async error => { if (error) { await nextTick(); document.querySelector('dialog[open][aria-labelledby="auth-preview-heading"] [role="alert"]')?.focus() } })
let controller, saveController, impactController, run = 0, operationId
const writable = computed(() => { void store.revision; return ['roles', 'sites'].includes(entity.value) ? provider.isSystem() : provider.canAny(ENTITIES[entity.value].write, store.siteId) })
const writeReason = computed(() => ['roles', 'sites'].includes(entity.value) ? '仅系统管理员可维护' : '当前身份只有查询权限')
function editable(row) { return writable.value && (!row.builtin || entity.value === 'accounts' && row.id !== 'demo-system' && provider.isSystem()) && (entity.value !== 'dutyShifts' || row.enabled && Date.parse(row.startsAt) > Date.now()) }
function displayTime(value) { return localTime(value, currentSite.value?.timezone || 'UTC').replace('T', ' ') || '未知' }
const tableColumns = computed(() => masterColumns(entity.value, options.value, trees.value, currentSite.value, displayTime))
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
    if (list.value.total != null && pageNum.value > Math.max(1, Math.ceil(list.value.total / pageSize.value))) { setPage(Math.max(1, Math.ceil(list.value.total / pageSize.value))); return }
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
async function allowLeave() { if (busy.value) return false; if ((dirty.value || resetReason.value || resetPassword.value || resetConfirmed.value) && !await confirmDiscard()) return false; dirty.value = false; editorOpen.value = false; preview.value = null; pending.value = null; resetAccount.value = null; resetReason.value = ''; resetPassword.value = ''; resetConfirmed.value = false; return true }
store.leaveGuard = allowLeave
function openEditor(row) { editing.value = row ? JSON.parse(JSON.stringify(row)) : null; editorOptions.value = JSON.parse(JSON.stringify(options.value)); editorKey.value++; operationId = crypto.randomUUID(); dirty.value = false; saveError.value = null; selected.value = null; editorOpen.value = true }
async function closeEditor() { if (await allowLeave()) editorOpen.value = false }
function relatedVersions() { return Object.fromEntries(Object.values(editorOptions.value).filter(Array.isArray).flat().map(r => [r.id, r.version])) }
async function save(data) {
  busy.value = true; saveError.value = null; saveController = new AbortController()
  try {
    const type = `${entity.value}.${editing.value ? 'update' : 'create'}`, command = { siteId: store.siteId, id: editing.value?.id, expectedVersion: editing.value?.version, operationId, relatedVersions: relatedVersions(), data }
    if (editing.value && ['accounts', 'roles'].includes(entity.value) && await preparePreview(type, command)) return
    const result = await provider.execute(type, command, { signal: saveController.signal })
    busy.value = false; dirty.value = false; editorOpen.value = false; notice.value = `已保存${ENTITIES[entity.value].title}“${result.data.name}”。`; await load()
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
  try { const { row, remove } = action.value; const type = `${entity.value}.${remove ? 'delete' : 'status'}`, command = { siteId: store.siteId, id: row.id, expectedVersion: row.version, enabled: !row.enabled, operationId }; if (entity.value === 'roles' && await preparePreview(type, command)) return; await provider.execute(type, command, { signal: saveController.signal }); busy.value = false; action.value = null; notice.value = '操作已完成，相关记录未级联修改。'; await load() }
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
function openReset(row) { resetAccount.value = row; resetReason.value = ''; resetPassword.value = ''; resetConfirmed.value = false; resetLocalErrors.value = {}; saveError.value = null; operationId = crypto.randomUUID() }
async function closeReset() { if (await allowLeave()) resetAccount.value = null }
async function resetCredential() {
  if (busy.value) return
  resetLocalErrors.value = {}
  if (resetPassword.value.length < 8 || resetPassword.value.length > 72) resetLocalErrors.value.password = '请输入8至72位新登录密码'
  if (!resetReason.value.trim()) resetLocalErrors.value.reason = '请填写重置原因'
  if (!resetConfirmed.value) resetLocalErrors.value.confirm = '请确认重置密码并使已有会话失效'
  if (Object.keys(resetLocalErrors.value).length) { await focusResetErrors(); return }
  busy.value = true; saveError.value = null; saveController = new AbortController()
  try { await provider.execute('accounts.resetCredential', { siteId: store.siteId, id: resetAccount.value.id, expectedVersion: resetAccount.value.version, operationId, reason: resetReason.value, password: resetPassword.value, confirm: resetConfirmed.value }, { signal: saveController.signal }); resetAccount.value = null; resetReason.value = ''; resetPassword.value = ''; resetConfirmed.value = false; notice.value = '登录密码已重置，该账号的已有会话已失效。'; await load() }
  catch (e) { if (e.name !== 'AbortError') saveError.value = e }
  finally { busy.value = false }
}
const unsubscribe = provider.subscribe(({ kind }) => { if (['identity', 'expired', 'reset', 'authorization'].includes(kind)) { saveController?.abort(); editorOpen.value = false; dirty.value = false; action.value = null; preview.value = null; pending.value = null; resetAccount.value = null; resetReason.value = '' } })
watch(() => [route.fullPath, store.siteId, store.revision, entity.value], () => {
  keyword.value = query.value.keyword || ''; status.value = query.value.status || ''; organizationId.value = query.value.organizationId || ''; areaId.value = query.value.areaId || ''; load()
}, { immediate: true })
watch(() => store.siteId, () => { editorOpen.value = false; dirty.value = false; action.value = null; selected.value = null; saveController?.abort(); impactController?.abort() })
onBeforeUnmount(() => { unsubscribe(); run++; controller?.abort(); saveController?.abort(); impactController?.abort(); if (store.leaveGuard === allowLeave) store.leaveGuard = null })
</script>
