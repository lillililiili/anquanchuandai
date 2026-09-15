<template>
  <div class="app-container">
    <ModuleHeader module="system" title="区域资料" description="只维护厂站内区域/设施/楼层名称，不表示实时定位。" />
    <el-row class="mb8">
      <el-button v-if="canWrite" type="primary" icon="Plus" @click="openForm()">新增区域</el-button>
    </el-row>
    <el-table v-loading="loading" class="custom-table" :data="list">
      <template #empty><BrandedEmpty compact description="暂无区域资料" /></template>
      <el-table-column label="名称" prop="name" min-width="160" show-overflow-tooltip />
      <el-table-column align="center" label="类型" min-width="160">
        <template #default="scope">{{ typeLabel(scope.row.spaceType) }}</template>
      </el-table-column>
      <el-table-column align="center" label="状态" min-width="160">
        <template #default="scope"><el-tag :type="scope.row.status === '1' ? 'info' : 'success'" size="small">{{ scope.row.status === '1' ? '停用' : '启用' }}</el-tag></template>
      </el-table-column>
      <el-table-column v-if="canWrite" align="center" label="操作" min-width="160"><template #default="scope"><el-button link type="primary" @click="openForm(scope.row)">编辑</el-button><el-button link :type="scope.row.status === '0' ? 'danger' : 'success'" @click="toggle(scope.row)">{{ scope.row.status === '0' ? '停用' : '恢复' }}</el-button></template></el-table-column>
    </el-table>
    <el-dialog v-model="open" :title="form.id ? '编辑区域' : '新增区域'" width="420px">
      <el-form label-width="80px">
        <el-form-item label="名称"><el-input v-model="form.name" /></el-form-item>
        <el-form-item label="类型">
          <el-select v-model="form.spaceType" :disabled="!!form.id">
            <el-option label="区域" value="area" />
            <el-option label="设施" value="facility" />
            <el-option label="楼层" value="floor" />
          </el-select>
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="open = false">取消</el-button>
        <el-button type="primary" @click="submit">保存</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup>
import { listSpaces, createSpace, updateSpace, changeSpaceStatus } from '@/api/wear/people'
import useUserStore from '@/store/modules/user'

const userStore = useUserStore()
const { proxy } = getCurrentInstance()
const canWrite = computed(() => userStore.canWritePerson)
const loading = ref(false)
const list = ref([])
const open = ref(false)
const form = reactive({ id: '', name: '', spaceType: 'area', version: 1 })

function unwrap(res) { return res && res.data !== undefined ? res.data : res }

function typeLabel(type) {
  if (type === 'facility') return '设施'
  if (type === 'floor') return '楼层'
  return '区域'
}

function getList() {
  loading.value = true
  listSpaces({ status: 'all' }).then(res => { list.value = unwrap(res) || [] }).finally(() => { loading.value = false })
}

function openForm(row = {}) { Object.assign(form, { id: row.id || '', name: row.name || '', spaceType: row.spaceType || 'area', version: Number(row.version || 1) }); open.value = true }

function submit() {
  const req = form.id ? updateSpace(form.id, { name: form.name, version: form.version }) : createSpace(form)
  req.then(() => {
    proxy.$modal.msgSuccess('已保存')
    open.value = false
    getList()
  })
}

function toggle(row) { proxy.$modal.confirm(`确认${row.status === '0' ? '停用' : '恢复'}“${row.name}”吗？`).then(() => changeSpaceStatus(row.id, { status: row.status === '0' ? '1' : '0', version: Number(row.version) })).then(() => { proxy.$modal.msgSuccess('状态已更新'); getList() }).catch(() => {}) }

function onSiteChanged() { getList() }
onMounted(() => {
  getList()
  window.addEventListener('site-changed', onSiteChanged)
})
onUnmounted(() => window.removeEventListener('site-changed', onSiteChanged))
</script>
