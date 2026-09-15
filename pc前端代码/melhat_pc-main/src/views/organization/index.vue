<template>
  <div class="app-container">
    <ModuleHeader title="组织资料" description="维护班组与承包商。停用后不再用于新增人员，历史归属继续保留。" />
    <el-tabs v-model="activeTab" class="ledger-tabs">
      <el-tab-pane label="班组" name="teams">
        <div class="page-toolbar"><el-button v-if="canWrite" type="primary" icon="Plus" @click="openForm('team')">新增班组</el-button></div>
        <el-table v-loading="loading" class="custom-table" :data="teams">
          <template #empty><BrandedEmpty compact description="暂无班组" /></template>
          <el-table-column label="班组名称" prop="name" min-width="160" show-overflow-tooltip />
          <el-table-column label="厂站" min-width="160" show-overflow-tooltip><template #default="scope">{{ siteName(scope.row.siteId) }}</template></el-table-column>
          <el-table-column align="center" label="状态" min-width="160"><template #default="scope"><el-tag :type="scope.row.status === '0' ? 'success' : 'info'" size="small">{{ statusLabel(scope.row.status) }}</el-tag></template></el-table-column>
          <el-table-column v-if="canWrite" align="center" label="操作" min-width="160"><template #default="scope"><el-button link type="primary" @click="openForm('team', scope.row)">编辑</el-button><el-button link :type="scope.row.status === '0' ? 'danger' : 'success'" @click="toggle('team', scope.row)">{{ scope.row.status === '0' ? '停用' : '恢复' }}</el-button></template></el-table-column>
        </el-table>
      </el-tab-pane>
      <el-tab-pane label="承包商" name="contractors">
        <div class="page-toolbar"><el-button v-if="canWrite" type="primary" icon="Plus" @click="openForm('contractor')">新增承包商</el-button></div>
        <el-table v-loading="loading" class="custom-table" :data="contractors">
          <template #empty><BrandedEmpty compact description="暂无承包商" /></template>
          <el-table-column label="承包商名称" prop="name" min-width="180" show-overflow-tooltip />
          <el-table-column align="center" label="状态" min-width="180"><template #default="scope"><el-tag :type="scope.row.status === '0' ? 'success' : 'info'" size="small">{{ statusLabel(scope.row.status) }}</el-tag></template></el-table-column>
          <el-table-column v-if="canWrite" align="center" label="操作" min-width="180"><template #default="scope"><el-button link type="primary" @click="openForm('contractor', scope.row)">编辑</el-button><el-button link :type="scope.row.status === '0' ? 'danger' : 'success'" @click="toggle('contractor', scope.row)">{{ scope.row.status === '0' ? '停用' : '恢复' }}</el-button></template></el-table-column>
        </el-table>
      </el-tab-pane>
    </el-tabs>
    <el-dialog v-model="formOpen" :title="dialogTitle" width="440px" destroy-on-close>
      <el-form ref="formRef" :model="form" :rules="rules" label-width="96px">
        <el-form-item label="名称" prop="name"><el-input v-model="form.name" maxlength="80" show-word-limit /></el-form-item>
        <el-form-item v-if="form.kind === 'team'" label="所属厂站"><el-input :model-value="currentSiteName" disabled /></el-form-item>
      </el-form>
      <template #footer><el-button @click="formOpen = false">取消</el-button><el-button type="primary" :loading="submitting" @click="submit">保存更改</el-button></template>
    </el-dialog>
  </div>
</template>

<script setup>
import { listTeams, listContractors, createTeam, createContractor, updateTeam, updateContractor } from '@/api/wear/people'
import useUserStore from '@/store/modules/user'
const userStore = useUserStore(); const { proxy } = getCurrentInstance()
const canWrite = computed(() => userStore.canWritePerson); const loading = ref(false); const submitting = ref(false); const activeTab = ref('teams')
const teams = ref([]); const contractors = ref([]); const formOpen = ref(false); const formRef = ref(); const form = reactive({ kind: 'team', id: '', name: '', status: '0' })
const rules = { name: [{ required: true, message: '请输入名称', trigger: 'blur' }] }
const currentSiteName = computed(() => userStore.sites.find(item => String(item.id) === String(userStore.currentSiteId))?.name || '当前厂站')
const dialogTitle = computed(() => `${form.id ? '编辑' : '新增'}${form.kind === 'team' ? '班组' : '承包商'}`)
function unwrap(res) { return res?.data !== undefined ? res.data : res }
function statusLabel(status) { return status === '0' ? '启用' : '停用' }
function siteName(id) { return userStore.sites.find(item => String(item.id) === String(id))?.name || '当前厂站' }
function load() { loading.value = true; Promise.all([listTeams({ status: 'all' }), listContractors({ status: 'all' })]).then(([a,b]) => { teams.value = unwrap(a) || []; contractors.value = unwrap(b) || [] }).finally(() => { loading.value = false }) }
function openForm(kind, row = {}) { Object.assign(form, { kind, id: row.id || '', name: row.name || '', status: row.status || '0' }); formOpen.value = true }
function toggle(kind, row) { proxy.$modal.confirm(`确认${row.status === '0' ? '停用' : '恢复'}“${row.name}”吗？`).then(() => kind === 'team' ? updateTeam(row.id, { status: row.status === '0' ? '1' : '0' }) : updateContractor(row.id, { status: row.status === '0' ? '1' : '0' })).then(() => { proxy.$modal.msgSuccess('状态已更新'); load() }).catch(() => {}) }
function submit() { formRef.value.validate(valid => { if (!valid) return; submitting.value = true; const payload = { name: form.name.trim() }; const req = form.kind === 'team' ? (form.id ? updateTeam(form.id, payload) : createTeam({ ...payload, siteId: userStore.currentSiteId })) : (form.id ? updateContractor(form.id, payload) : createContractor(payload)); req.then(() => { proxy.$modal.msgSuccess('保存成功'); formOpen.value = false; load() }).finally(() => { submitting.value = false }) }) }
function onSiteChanged() { load() }
onMounted(() => { load(); window.addEventListener('site-changed', onSiteChanged) }); onUnmounted(() => window.removeEventListener('site-changed', onSiteChanged))
</script>
