<template>
  <section>
    <h1 class="sr-only">{{ route.meta.title }}</h1>
    <nav class="workspace-tabs" aria-label="功能导航"><router-link v-for="item in WORKSPACES.filter(x => x.group === route.meta.group)" :key="item.path" :class="{ active: item.path === route.path }" :to="{ path: item.path, query: { siteId: store.siteId } }">{{ item.title }}</router-link></nav>
    <p v-if="notice" class="notice" role="status">{{ notice }}</p>
    <p v-if="dutyError" class="notice error" role="alert">{{ dutyError.message }}</p>
    <div :class="{ 'people-organization-layout': entity === 'people' }">
      <OrganizationSidebar v-if="entity === 'people'" :nodes="trees.organizations || []" :selected-id="organizationId" :loading="treeLoading" :error="treeError" :data="treeData" :writable="organizationWritable" @select="selectOrganization" @inspect="organizationDetail = $event" @retry="loadOrganizations" @create="openOrganizationEditor" @edit="row => openEditor(row, 'organizations')" @delete="row => prepareStatus(row, true, 'organizations')" />
    <section class="panel master-list">

      <form class="list-filters" @submit.prevent="search"><label>{{ entity === 'roles' ? '角色名称关键词' : '编号 / 名称关键词' }}<input v-model="keyword" maxlength="100" placeholder="输入关键词" /></label><label v-if="entity === 'people'">在岗状态<UiSelect v-model="dutyStatus"><option value="">全部状态</option><option v-for="(label, value) in PERSON_DUTY_STATUSES" :key="value" :value="value">{{ label }}</option></UiSelect></label><label v-else>启停状态<UiSelect v-model="status"><option value="">全部状态</option><option value="enabled">启用</option><option value="disabled">停用</option></UiSelect></label><div class="filter-actions"><button class="button primary" type="submit">查询</button><button class="button" type="button" @click="resetFilters">重置</button></div></form><div class="section-heading"><div><h2>{{ ENTITIES[entity].title }}列表</h2><small v-if="entity === 'people'" class="muted">当前组织：{{ selectedOrganization?.name || (organizationId ? '组织不存在或不可见' : '全部组织') }}<span v-if="selectedOrganization">（含下级）</span></small><small v-else class="muted">{{ currentSite?.name }} · 授权范围</small></div><div><button v-if="!TEST_SITE_MODE || entity !== 'sites'" class="button primary" :disabled="!writable || busy || loading || !!loadError || list?.availability !== 'AVAILABLE'" @click="openEditor(null)">新增{{ ENTITIES[entity].title }}</button><small v-if="!writable" class="disabled-reason">{{ writeReason }}</small><small v-else-if="loading || loadError || list?.availability !== 'AVAILABLE'" class="disabled-reason">请先完成资料查询</small></div></div>
      <div v-table-region class="admin-results"><QueryState :data="list" :error="loadError" :loading="loading" @retry="load">
        <div v-if="list?.rows?.length" class="table-scroll">
          <table v-table class="admin-table">
            <thead><tr>
              <th :data-width="entity === 'people' ? 140 : 180" class="pinned-key">{{ entity === 'roles' ? '角色名称' : '名称' }}</th>
              <th v-if="!['dutyShifts', 'roles'].includes(entity)" :data-width="entity === 'people' ? 120 : 180">{{ entity === 'accounts' ? '登录名' : '编号 / 标识' }}</th>
              <th v-for="column in tableColumns" :key="column.key" :data-width="column.width || 180" :class="column.numeric ? 'number-cell' : ''">{{ column.label }}</th>
              <th data-width="100" class="status-cell">{{ entity === 'people' ? '在岗状态' : '状态' }}</th>
              <th v-if="!['people', 'accounts', 'sites', 'dutyShifts', 'roles'].includes(entity)" :data-width="entity === 'people' ? 60 : 80" class="number-cell">版本</th>
              <th :data-width="entity === 'dutyShifts' ? 160 : entity === 'people' ? 310 : entity === 'roles' ? 280 : 220" class="table-actions pinned-actions">操作</th>
            </tr></thead>
            <tbody><tr v-for="row in list.rows" :key="row.id" :class="{ 'selected-row': selected?.id === row.id }">
              <td class="pinned-key"><button class="record-name" @click="inspect(row)">{{ displayName(row) }}</button></td>
              <td v-if="!['dutyShifts', 'roles'].includes(entity)">{{ row.code || row.loginName || row.id }}</td>
              <td v-for="column in tableColumns" :key="column.key" :class="column.numeric ? 'number-cell' : ''">{{ column.value(row) }}</td>
              <td class="status-cell"><span v-if="entity === 'people'" class="badge" :class="{ warning: normalizePersonDutyStatus(row.dutyStatus) !== 'ON_DUTY' }" :title="dutyStatusTitle(row)">{{ personDutyStatusLabel(row.dutyStatus) }}</span><span v-else class="badge" :class="{ warning: !row.enabled }">{{ row.enabled ? '启用' : '停用' }}</span></td>
              <td v-if="!['people', 'accounts', 'sites', 'dutyShifts', 'roles'].includes(entity)" class="number-cell">{{ row.version }}</td>
              <td class="table-actions pinned-actions"><div class="row-actions">
                <template v-if="entity === 'accounts'">
                  <button class="button" :disabled="!editable(row)" @click="openEditor(row)">编辑</button>
                  <button class="button" :disabled="!editable(row) || row.id === store.identity?.id" @click="prepareStatus(row)">{{ row.enabled ? '停用' : '启用' }}</button>
                  <button class="button danger" :disabled="!editable(row) || row.id === store.identity?.id" @click="prepareStatus(row, true)">删除</button>
                </template>
                <template v-else-if="entity === 'roles'">
                  <button class="button" @click="inspect(row)">查看</button>
                  <button class="button" :disabled="!editable(row)" @click="openEditor(row)">编辑</button>
                  <button class="button" :disabled="!editable(row)" @click="prepareStatus(row)">{{ row.enabled ? '停用' : '启用' }}</button>
                  <button class="button danger" :disabled="!editable(row)" @click="prepareStatus(row, true)">删除</button>
                </template>
                <template v-else-if="entity === 'sites'">
                  <button class="button" :disabled="!editable(row)" @click="openEditor(row)">编辑</button>
                  <button class="button" :disabled="!editable(row)" @click="prepareStatus(row)">{{ row.enabled ? '停用' : '启用' }}</button>
                </template>
                <template v-else-if="entity === 'dutyShifts'">
                  <button class="button" :disabled="!editable(row)" @click="openEditor(row)">编辑</button>
                  <button class="button" :disabled="!editable(row)" :title="!editable(row) ? (!writable ? writeReason : '已开始或已停用的班次不能停用') : undefined" @click="prepareStatus(row)">停用</button>
                </template>
                <template v-else>
                  <button class="button" :disabled="busy" @click="inspect(row)">查看</button>
                  <button class="button" :disabled="!editable(row) || busy" @click="openEditor(row)">编辑</button>
                  <button v-if="entity === 'people'" class="button danger" :disabled="!editable(row) || busy" @click="prepareStatus(row, true)">删除</button>
                  <RowMore>
                    <template v-if="entity === 'people'"><button v-if="normalizePersonDutyStatus(row.dutyStatus) !== 'ON_DUTY'" class="button" :disabled="!editable(row) || busy || loading" @click="setPersonDutyStatus(row, 'ON_DUTY')">设为在岗</button><button v-if="normalizePersonDutyStatus(row.dutyStatus) !== 'OFF_DUTY'" class="button" :disabled="!editable(row) || busy || loading" @click="setPersonDutyStatus(row, 'OFF_DUTY')">设为离岗</button><AssignmentEntry :person-id="row.id" :disabled="!row.enabled || busy || loading" reason="需人员档案启用且当前无待完成操作" /><AssignmentEntry mode="return" :person-id="row.id" :disabled="busy || loading" /></template>
                    <button v-else class="button" :disabled="!editable(row)" @click="prepareStatus(row)">{{ row.enabled ? '停用' : '启用' }}</button>
                    <button v-if="entity === 'organizations'" class="button danger" :disabled="!editable(row)" @click="prepareStatus(row, true)">删除</button>
                    <small v-if="!editable(row)" class="disabled-reason">{{ row.builtin ? '内置记录受保护' : writeReason }}</small>
                  </RowMore>
                </template>
              </div></td>
            </tr></tbody>
          </table>
        </div>
        <div v-else class="query-state"><strong>无匹配记录</strong><p>可调整筛选，或在有维护权限时新增{{ ENTITIES[entity].title }}。</p></div>
        <AdminPagination v-if="list?.total !== undefined" :total="list.total" :model-value="pageNum" :page-size="pageSize" :disabled="loading" @update:model-value="setPage" @update:page-size="setPageSize(String($event))" />
      </QueryState></div>
    </section>
    </div>
    <ModalPanel heading-id="organization-detail-heading" :open="!!organizationDetail" title="组织详情" @close="organizationDetail = null">
      <dl v-if="organizationDetail" class="record-fields">
        <dt>组织名称</dt><dd>{{ organizationDetail.name }}</dd>
        <dt>组织编号</dt><dd>{{ organizationDetail.code || '—' }}</dd>
        <dt>上级组织</dt><dd>{{ organizationDetail.parentId ? (trees.organizations?.find(row => row.id === organizationDetail.parentId)?.name || '当前不可见') : '无上级组织' }}</dd>
      </dl>
    </ModalPanel>
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
        <p v-if="resetFormError" data-form-error tabindex="-1" class="error" role="alert">{{ resetFormError }}</p></div><div class="dialog-form-footer"><button type="button" class="button" :disabled="busy" @click="closeReset">取消</button><button class="button primary" :disabled="busy">{{ busy ? '正在保存…' : '保存' }}</button></div>
      </form>
    </ModalPanel>
    <ModalPanel layout="form" :size="['accounts', 'roles', 'dutyShifts'].includes(editorEntity) ? 'wide' : 'regular'" :open="editorOpen" :title="(editing ? '编辑' : '新增') + ENTITIES[editorEntity].title" @close="closeEditor">
      <MasterEditor v-if="editorOpen" :key="editorKey" :entity="editorEntity" :record="editing" :defaults="editorDefaults" :options="editorOptions" :site-id="store.siteId" :timezone="currentSite?.timezone || 'UTC'" :busy="busy" :error="saveError" :is-system="provider.isSystem()" @dirty="dirty = $event" @save="save" @close="closeEditor" />
    </ModalPanel>
    <ModalPanel heading-id="record-heading" :open="entity !== 'people' && !!selected && !editorOpen && !action" :title="ENTITIES[entity].title + ' · 只读详情'" @close="closeInspect">
      <button v-if="entity === 'accounts' && selected" class="button" :disabled="!editable(selected) || selected.id === store.identity?.id" @click="openReset(selected)">重置登录密码</button>
      <template v-if="selected">
        <dl v-if="entity === 'roles'" class="record-fields">
          <dt>角色名称</dt><dd>{{ selected.name }}</dd>
          <dt>状态</dt><dd>{{ selected.enabled ? '启用' : '停用' }}</dd>
          <dt>角色类型</dt><dd>{{ selected.builtin ? '内置角色' : '自定义角色' }}</dd>
          <dt>创建时间</dt><dd>{{ beijingTime(selected.createdAt) }}</dd>
          <dt>更新时间</dt><dd>{{ beijingTime(selected.updatedAt) }}</dd>
          <dt>操作</dt><dd>{{ roleOperationLabels(selected).join('、') || '未配置操作' }}</dd>
        </dl>
        <template v-else>
          <h3>{{ displayName(selected) }}</h3>
          <dl class="record-fields">
            <dt>标识</dt><dd>{{ selected.id }}</dd><dt>状态 / 版本</dt><dd>{{ selected.enabled ? '启用' : '停用' }} · v{{ selected.version }}</dd>
            <dt>关联信息</dt><dd>{{ summary(selected) }}</dd>
            <template v-if="entity === 'accounts'"><dt>关联人员</dt><dd>{{ options.people?.find(p => p.id === selected.personId)?.name || '未关联 / 当前不可见' }}</dd><dt>角色范围</dt><dd v-for="roleId in selected.roleIds" :key="roleId">{{ options.roles?.find(r => r.id === roleId)?.name || roleId }} · {{ roleSiteNames(roleId) }}</dd></template>
            <template v-if="entity === 'dutyShifts'"><dt>班次时间（{{ currentSite?.timezone || 'UTC' }}）</dt><dd>{{ displayTime(selected.startsAt) }} 至 {{ displayTime(selected.endsAt) }}</dd><dt>当时的成员名单</dt><dd>{{ selected.memberSnapshots?.map(p => p.name).join('、') }}</dd></template>
          </dl>
        </template>
      </template>
    </ModalPanel>
    <ModalPanel size="confirm" heading-id="impact-heading" :open="!!action" title="操作影响确认" @close="closeAction">
      <template v-if="action"><p>将{{ action.remove ? '删除' : action.row.enabled ? '停用' : '启用' }}：<strong>{{ displayName(action.row) }}</strong></p><p v-if="entity === 'accounts' && action.remove" class="notice">删除后该账号将无法登录，人员关联会解除，人员档案和装备记录保留。此操作不可恢复。</p><QueryState :data="impactData" :loading="impactLoading" :error="impactError" @retry="loadImpacts"><ul v-if="impactData?.rows?.length"><li v-for="r in impactData.rows" :key="r.label + r.id">{{ r.label }}：{{ r.name }}</li></ul><p v-else>未发现阻止本次操作的活动引用。</p></QueryState><p v-if="saveError" class="notice error" role="alert">{{ saveError.message }} · {{ saveError.errorCode }}</p></template><template v-if="action" #footer><button class="button" :disabled="busy" @click="closeAction">保留记录</button><button class="button danger" :disabled="busy || impactLoading || !!impactError || (action.row.enabled || action.remove) && !!impactData?.rows?.length" @click="confirmAction">{{ busy ? '正在处理…' : action.remove ? '确认删除' : '确认操作' }}</button></template>
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
import { roleOperationLabels } from '../operationLabels'
import { beijingTime } from '../tablePresentation'
import { localTime } from '../time'
import { TEST_SITE_MODE, TEST_SITE, testSiteName } from '../../shared/test-site.mjs'
import { PERSON_DUTY_STATUSES, normalizePersonDutyStatus, personDutyStatusLabel } from '../../shared/person-duty.mjs'
import { readTestSitePage } from '../testSiteView'
import ModalPanel from '../components/ModalPanel.vue'
import { useConfirmation } from '../confirmation'
import { useFormFeedback } from '../formFeedback'
const confirmDiscard = useConfirmation()
import QueryState from '../components/QueryState.vue'
import AssignmentEntry from '../components/AssignmentEntry.vue'
import MasterEditor from '../components/MasterEditor.vue'
import OrganizationSidebar from '../components/OrganizationSidebar.vue'
import AuthorizationPreview from '../components/AuthorizationPreview.vue'
const provider = getAdminProvider(), store = useAdminStore(), route = useRoute(), router = useRouter()
const entity = computed(() => route.meta.entity)
const currentSite = computed(() => store.sites.find(s => s.id === store.siteId))
const query = computed(() => { const cleaned = cleanQuery(route.query); if (entity.value === 'people') delete cleaned.status; else delete cleaned.dutyStatus; return cleaned }), pageNum = computed(() => Number(query.value.pageNum || 1)), pageSize = computed(() => Number(query.value.pageSize || 10))
const keyword = ref(query.value.keyword || ''), status = ref(query.value.status || ''), dutyStatus = ref(query.value.dutyStatus || ''), organizationId = ref(query.value.organizationId || '')
const list = ref(null), options = ref({}), trees = ref({}), loading = ref(false), loadError = ref(null), notice = ref(''), selected = ref(null)
const dutyError = ref(null)
const editorEntity = ref(entity.value), editorDefaults = ref({})
const organizationDetail = ref(null)
const treeLoading = ref(false), treeError = ref(null), treeData = ref(null)
const organizationWritable = computed(() => { void store.revision; return provider.canAny('organization:write', store.siteId) })
const selectedOrganization = computed(() => trees.value.organizations?.find(row => row.id === organizationId.value))
const editorOpen = ref(false), editing = ref(null), editorKey = ref(0), editorOptions = ref({}), dirty = ref(false), busy = ref(false), saveError = ref(null)
const action = ref(null), impactLoading = ref(false), impactError = ref(null), impactData = ref(null)
const preview = ref(null), pending = ref(null), resetAccount = ref(null), resetReason = ref(''), resetPassword = ref(''), resetConfirmed = ref(false)
const resetForm = computed(() => ({ password: resetPassword.value, reason: resetReason.value, confirm: resetConfirmed.value }))
const { formRef: resetFormRef, localErrors: resetLocalErrors, errors: resetErrors, formError: resetFormError, focusErrors: focusResetErrors } = useFormFeedback(resetForm, () => resetAccount.value ? saveError.value : null, 'reset-')
watch(saveError, async error => { if (error) { await nextTick(); document.querySelector('dialog[open][aria-labelledby="auth-preview-heading"] [role="alert"]')?.focus() } })
let controller, saveController, impactController, treeController, dutyController, run = 0, treeRun = 0, impactRun = 0, operationId
const writable = computed(() => { void store.revision; return ['roles', 'sites'].includes(entity.value) ? provider.isSystem() : provider.canAny(ENTITIES[entity.value].write, store.siteId) })
const writeReason = computed(() => ['roles', 'sites'].includes(entity.value) ? '仅系统管理员可维护' : '当前身份只有查询权限')
function editable(row) { return writable.value && (!row.builtin || entity.value === 'accounts' && row.id !== 'demo-system' && provider.isSystem()) && (entity.value !== 'dutyShifts' || row.enabled && Date.parse(row.startsAt) > Date.now()) }
function displayTime(value) { return localTime(value, currentSite.value?.timezone || 'UTC').replace('T', ' ') || '未知' }
function displayName(row) { return entity.value === 'sites' ? testSiteName(row) : row?.name }
function dutyStatusTitle(row) { return row.dutyStatusSource === 'MANUAL' ? `${row.dutyStatusUpdatedBy || '管理员'}于${beijingTime(row.dutyStatusUpdatedAt)}人工维护` : '尚未维护在岗状态' }
const tableColumns = computed(() => masterColumns(entity.value, options.value, trees.value, currentSite.value, displayTime))
function roleSiteNames(roleId) {
  const role = options.value.roles?.find(role => role.id === roleId)
  if (!role) return '角色已停用或当前不可见'
  const siteIds = [...new Set(role.grants.flatMap(grant => grant.siteIds))]
  return siteIds.map(id => options.value.sites?.find(site => site.id === id)?.name || id).join('、') || '未分配厂站'
}
function summary(row) {
  if (entity.value === 'people') return (options.value.organizations?.find(o => o.id === row.organizationId)?.name || '未关联或不可见')
  if (entity.value === 'sites') return row.timezone || 'UTC'
  if (entity.value === 'dutyShifts') return `${row.personIds.length} 人 · ${currentSite.value?.timezone || 'UTC'}`
  if (entity.value === 'accounts') return row.roleIds.length > 1 ? '历史多角色账号，请编辑并选择唯一角色' : row.roleIds.length ? (options.value.roles?.find(role => role.id === row.roleIds[0])?.name || '角色已停用或当前不可见') : '未分配角色'
  if (entity.value === 'roles') return row.grants.map(g => `${g.operations.length}项操作 / ${g.siteIds.length}个厂站`).join('；')
  return row.parentId ? '上级：' + (trees.value[entity.value]?.find(r => r.id === row.parentId)?.name || '未知') : '根节点'
}
async function load() {
  if (!ENTITIES[entity.value]) return
  const id = ++run; controller?.abort(); controller = new AbortController(); loading.value = true; loadError.value = null
  const input = { ...query.value, siteId: store.siteId, entity: entity.value, pageNum: pageNum.value, pageSize: pageSize.value, ...(entity.value === 'people' ? { includeDescendants: true } : {}) }
  try {
    const [res, choices] = await Promise.all([TEST_SITE_MODE && entity.value === 'sites' ? readTestSitePage(provider, input, { signal: controller.signal }) : provider.query('master', input, { signal: controller.signal }), provider.query('options', { siteId: store.siteId }, { signal: controller.signal })])
    if (id !== run) return
    list.value = res.data; options.value = choices.data
    if (list.value.total != null && pageNum.value > Math.max(1, Math.ceil(list.value.total / pageSize.value))) { setPage(Math.max(1, Math.ceil(list.value.total / pageSize.value))); return }
    selected.value = list.value.rows?.find(r => r.id === query.value.selectedId) || null
    if (query.value.selectedId && !selected.value && list.value.availability === 'AVAILABLE' && !(TEST_SITE_MODE && entity.value === 'sites' && query.value.selectedId !== TEST_SITE.adminId)) {
      try { const detail = await provider.query('record', { entity: entity.value, siteId: store.siteId, id: query.value.selectedId }, { signal: controller.signal }); if (id === run) selected.value = detail.data }
      catch (e) { if (id === run && e.name !== 'AbortError') notice.value = '原选中记录不存在或当前不可见，请重新选择。' }
    }
  } catch (e) { if (id === run && e.name !== 'AbortError') { loadError.value = e; if (e.code === 401) provider.invalidate() } }
  finally { if (id === run) loading.value = false }
}
async function loadOrganizations() {
  const id = ++treeRun; treeController?.abort(); treeController = new AbortController()
  treeLoading.value = true; treeError.value = null; treeData.value = null; trees.value = {}
  try {
    let rows = [], page = 1, total = 0
    do {
      const { data } = await provider.query('master', { entity: 'organizations', siteId: store.siteId, pageSize: 100, pageNum: page }, { signal: treeController.signal })
      if (id !== treeRun) return
      treeData.value = data
      if (data.availability !== 'AVAILABLE') return
      rows.push(...(data.rows || [])); total = data.total || 0; page++
      if (!data.rows?.length) break
    } while (rows.length < total)
    if (id === treeRun) trees.value = { organizations: rows }
  } catch (error) { if (id === treeRun && error.name !== 'AbortError') treeError.value = error }
  finally { if (id === treeRun) treeLoading.value = false }
}
function navigate(extra) { return router.replace({ path: route.path, query: { ...query.value, ...extra, siteId: store.siteId } }) }
function search() { navigate({ keyword: keyword.value, status: entity.value === 'people' ? undefined : status.value, dutyStatus: entity.value === 'people' ? dutyStatus.value : undefined, organizationId: organizationId.value || undefined, pageNum: '1', selectedId: undefined }) }
function resetFilters() { keyword.value = ''; status.value = ''; dutyStatus.value = ''; organizationId.value = ''; search() }
function setPage(page) { navigate({ pageNum: String(page), selectedId: undefined }) }
function setPageSize(size) { navigate({ pageNum: '1', pageSize: size, selectedId: undefined }) }
function selectOrganization(row) { return navigate({ organizationId: row?.id || undefined, selectedId: undefined, pageNum: '1' }) }
function inspect(row) {
  if (entity.value === 'people') router.push({ path: `/people/${row.id}`, query: { siteId: store.siteId, returnTo: route.path + '?' + new URLSearchParams({ ...query.value, selectedId: row.id, siteId: store.siteId }).toString() } })
  else { selected.value = row; navigate({ selectedId: row.id }) }
}
function closeInspect() { selected.value = null; navigate({ selectedId: undefined }) }
async function allowLeave() { if (busy.value) return false; if ((dirty.value || resetReason.value || resetPassword.value || resetConfirmed.value) && !await confirmDiscard()) return false; dirty.value = false; organizationDetail.value = null; editorOpen.value = false; preview.value = null; pending.value = null; resetAccount.value = null; resetReason.value = ''; resetPassword.value = ''; resetConfirmed.value = false; return true }
store.leaveGuard = allowLeave
function openOrganizationEditor(parent) { openEditor(null, 'organizations', { parentId: parent?.id || '' }) }
function openEditor(row, targetEntity = entity.value, defaults = {}) {
  if (busy.value) return
  if (TEST_SITE_MODE && targetEntity === 'sites' && (!row || row.id !== TEST_SITE.adminId)) return
  editorEntity.value = targetEntity
  editorDefaults.value = row ? {} : targetEntity === 'people' && selectedOrganization.value ? { organizationId: selectedOrganization.value.id } : defaults
  editing.value = row ? JSON.parse(JSON.stringify(row)) : null
  const choices = targetEntity === 'organizations' ? { ...options.value, organizations: (trees.value.organizations || []) } : options.value
  editorOptions.value = JSON.parse(JSON.stringify(choices))
  editorKey.value++; operationId = crypto.randomUUID(); dirty.value = false; saveError.value = null; selected.value = null; editorOpen.value = true
}
async function closeEditor() { if (await allowLeave()) editorOpen.value = false }
async function setPersonDutyStatus(row, value) {
  if (entity.value !== 'people' || busy.value || loading.value || !editable(row) || !['ON_DUTY', 'OFF_DUTY'].includes(value) || normalizePersonDutyStatus(row.dutyStatus) === value) return
  const siteId = store.siteId, request = new AbortController()
  dutyController = request; busy.value = true; dutyError.value = null; notice.value = ''
  try {
    await provider.execute('people.dutyStatus', { siteId, id: row.id, expectedVersion: row.version, operationId: crypto.randomUUID(), dutyStatus: value }, { signal: request.signal })
    if (request.signal.aborted || siteId !== store.siteId || entity.value !== 'people') return
    notice.value = `已将“${row.name}”设为${personDutyStatusLabel(value)}。`
    busy.value = false
    await load()
  } catch (error) {
    if (!request.signal.aborted && error.name !== 'AbortError') {
      dutyError.value = error
      if (error.code === 401) provider.invalidate()
      else if (error.code === 409) { busy.value = false; await load() }
    }
  } finally { if (dutyController === request) { dutyController = null; busy.value = false } }
}
function cancelDutyUpdate() { if (dutyController) { dutyController.abort(); dutyController = null; busy.value = false }; dutyError.value = null }
function relatedVersions() { return Object.fromEntries(Object.values(editorOptions.value).filter(Array.isArray).flat().map(r => [r.id, r.version])) }
async function save(data) {
  busy.value = true; saveError.value = null; saveController = new AbortController()
  try {
    const type = `${editorEntity.value}.${editing.value ? 'update' : 'create'}`, command = { siteId: store.siteId, id: editing.value?.id, expectedVersion: editing.value?.version, operationId, relatedVersions: relatedVersions(), data }
    if (editing.value && ['accounts', 'roles'].includes(editorEntity.value) && await preparePreview(type, command)) return
    const result = await provider.execute(type, command, { signal: saveController.signal })
    busy.value = false; dirty.value = false; editorOpen.value = false; notice.value = `已保存${ENTITIES[editorEntity.value].title}“${result.data.name}”。`; await load(); if (editorEntity.value === 'organizations') await loadOrganizations()
  } catch (e) { if (e.name !== 'AbortError') { saveError.value = e; if (e.code === 401) provider.invalidate() } }
  finally { busy.value = false }
}
async function loadImpacts() {
  if (!action.value) return
  const id = ++impactRun, currentAction = action.value
  impactController?.abort(); impactController = new AbortController(); impactLoading.value = true; impactError.value = null; impactData.value = null
  try {
    const result = await provider.query('impacts', { siteId: store.siteId, entity: currentAction.entity, id: currentAction.row.id, all: currentAction.remove }, { signal: impactController.signal })
    if (id === impactRun) impactData.value = result.data
  } catch (error) { if (id === impactRun && error.name !== 'AbortError') impactError.value = error }
  finally { if (id === impactRun) impactLoading.value = false }
}
function prepareStatus(row, remove = false, targetEntity = entity.value) { if (targetEntity === 'organizations' && !remove) return; selected.value = null; action.value = { row, remove, entity: targetEntity }; saveError.value = null; operationId = crypto.randomUUID(); loadImpacts() }
function closeAction() { if (!busy.value) { impactRun++; action.value = null; impactController?.abort() } }
async function confirmAction() {
  busy.value = true; saveError.value = null; saveController = new AbortController()
  try { const { row, remove, entity: targetEntity } = action.value; const type = `${targetEntity}.${remove ? 'delete' : 'status'}`, command = { siteId: store.siteId, id: row.id, expectedVersion: row.version, ...(remove ? {} : { enabled: !row.enabled }), operationId }; if (targetEntity === 'roles' && !remove && await preparePreview(type, command)) return; await provider.execute(type, command, { signal: saveController.signal }); busy.value = false; action.value = null; notice.value = remove ? (targetEntity === 'accounts' ? '账号已删除。' : targetEntity === 'roles' ? '角色已删除。' : targetEntity === 'people' ? '人员已删除。' : '记录已删除。') : '状态已更新。'; if (targetEntity === 'organizations') { await loadOrganizations(); if (remove && organizationId.value === row.id) await selectOrganization(null) }; await load() }
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
  try { await provider.execute(pending.value.type, JSON.parse(JSON.stringify({ ...pending.value.command, previewId: preview.value.previewId })), { signal: saveController.signal }); dirty.value = false; editorOpen.value = false; action.value = null; preview.value = null; pending.value = null; notice.value = '授权已更新。'; await load() }
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
const unsubscribe = provider.subscribe(({ kind }) => { if (['identity', 'expired', 'reset', 'authorization'].includes(kind)) { cancelDutyUpdate(); organizationDetail.value = null; impactRun++; impactController?.abort(); saveController?.abort(); editorOpen.value = false; dirty.value = false; action.value = null; preview.value = null; pending.value = null; resetAccount.value = null; resetReason.value = '' } })
watch(() => [route.fullPath, store.siteId, store.revision, entity.value], () => {
  keyword.value = query.value.keyword || ''; status.value = query.value.status || ''; dutyStatus.value = query.value.dutyStatus || ''; organizationId.value = query.value.organizationId || ''; load()
}, { immediate: true })
watch(() => [store.siteId, store.revision, entity.value], () => { if (entity.value === 'people') loadOrganizations(); else { treeRun++; treeController?.abort(); trees.value = {}; treeData.value = null } }, { immediate: true })
watch(entity, cancelDutyUpdate)
watch(() => store.siteId, () => { cancelDutyUpdate(); organizationDetail.value = null; impactRun++; editorOpen.value = false; dirty.value = false; action.value = null; selected.value = null; saveController?.abort(); impactController?.abort() })
onBeforeUnmount(() => { cancelDutyUpdate(); unsubscribe(); run++; treeRun++; impactRun++; treeController?.abort(); controller?.abort(); saveController?.abort(); impactController?.abort(); if (store.leaveGuard === allowLeave) store.leaveGuard = null })
</script>
