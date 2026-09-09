<template>
  <div class="app-container">
    <ModuleHeader module="system" title="区域资料" description="只维护厂站内区域/设施/楼层名称，不表示实时定位。" />
    <el-row class="mb8">
      <el-button v-if="canWrite" type="primary" icon="Plus" @click="open = true">新增区域</el-button>
    </el-row>
    <el-table v-loading="loading" class="custom-table" :data="list">
      <template #empty><BrandedEmpty compact description="暂无区域资料" /></template>
      <el-table-column label="名称" prop="name" />
      <el-table-column label="类型" width="120">
        <template #default="scope">{{ typeLabel(scope.row.spaceType) }}</template>
      </el-table-column>
      <el-table-column label="状态" width="80">
        <template #default="scope">{{ scope.row.status === '1' ? '停用' : '正常' }}</template>
      </el-table-column>
    </el-table>
    <el-dialog v-model="open" title="新增区域" width="420px">
      <el-form label-width="80px">
        <el-form-item label="名称"><el-input v-model="form.name" /></el-form-item>
        <el-form-item label="类型">
          <el-select v-model="form.spaceType">
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
import { listSpaces, createSpace } from '@/api/wear/people'
import useUserStore from '@/store/modules/user'

const userStore = useUserStore()
const { proxy } = getCurrentInstance()
const canWrite = computed(() => userStore.canWritePerson)
const loading = ref(false)
const list = ref([])
const open = ref(false)
const form = reactive({ name: '', spaceType: 'area' })

function unwrap(res) { return res && res.data !== undefined ? res.data : res }

function typeLabel(type) {
  if (type === 'facility') return '设施'
  if (type === 'floor') return '楼层'
  return '区域'
}

function getList() {
  loading.value = true
  listSpaces().then(res => { list.value = unwrap(res) || [] }).finally(() => { loading.value = false })
}

function submit() {
  createSpace(form).then(() => {
    proxy.$modal.msgSuccess('已保存')
    open.value = false
    getList()
  })
}

function onSiteChanged() { getList() }
onMounted(() => {
  getList()
  window.addEventListener('site-changed', onSiteChanged)
})
onUnmounted(() => window.removeEventListener('site-changed', onSiteChanged))
</script>
