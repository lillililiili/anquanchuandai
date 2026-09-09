<template>
  <div class="app-container">
    <ModuleHeader
      module="system"
      title="围栏规则"
      description="仅多边形、WGS84。陈旧或未知点不会判违章。禁用不清历史事件。"
    />
    <el-row class="mb8">
      <el-button v-if="canEdit" type="primary" icon="Plus" @click="openForm()">新增围栏</el-button>
    </el-row>
    <el-table v-loading="loading" class="custom-table" :data="list">
      <template #empty><BrandedEmpty compact description="暂无围栏规则" /></template>
      <el-table-column label="名称" prop="name" />
      <el-table-column label="启用" width="80">
        <template #default="scope">{{ scope.row.enabled ? '是' : '否' }}</template>
      </el-table-column>
      <el-table-column label="适用" width="100">
        <template #default="scope">{{ scope.row.applyMode === 'persons' ? '指定人员' : '全厂站' }}</template>
      </el-table-column>
      <el-table-column label="规则版本" prop="ruleVersion" width="100" />
      <el-table-column label="防抖秒" prop="debounceSeconds" width="90" />
      <el-table-column label="标记" width="72">
        <template #default="scope"><el-tag v-if="scope.row.demo" type="warning" size="small">演示</el-tag></template>
      </el-table-column>
      <el-table-column v-if="canEdit" label="操作" width="160">
        <template #default="scope">
          <el-button link type="primary" @click="toggle(scope.row)">{{ scope.row.enabled ? '禁用' : '启用' }}</el-button>
        </template>
      </el-table-column>
    </el-table>
    <pagination v-show="total > 0" v-model:page="queryParams.current" v-model:limit="queryParams.size" :total="total" @pagination="getList" />

    <el-dialog v-model="formOpen" title="新增围栏" width="520px">
      <el-form label-width="100px">
        <el-form-item label="名称"><el-input v-model="form.name" /></el-form-item>
        <el-form-item label="多边形JSON">
          <el-input v-model="form.polygonText" type="textarea" rows="4" placeholder='[{"lng":117.10,"lat":36.10},...]' />
        </el-form-item>
        <el-form-item label="适用">
          <el-select v-model="form.applyMode" class="w-180">
            <el-option label="全厂站" value="all_site" />
            <el-option label="指定人员" value="persons" />
          </el-select>
        </el-form-item>
        <el-form-item v-if="form.applyMode === 'persons'" label="适用人员">
          <el-select v-model="form.personIds" multiple filterable class="w-180" placeholder="选择人员">
            <el-option v-for="p in people" :key="p.id" :label="p.name + ' ' + p.personCode" :value="p.id" />
          </el-select>
        </el-form-item>
        <el-form-item label="时段">
          <el-input v-model="form.timeStart" class="w-140" placeholder="HH:mm 空=全天" />
          <el-input v-model="form.timeEnd" class="w-140" placeholder="HH:mm" />
        </el-form-item>
        <el-form-item label="防抖秒"><el-input v-model="form.debounceSeconds" /></el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="formOpen = false">取消</el-button>
        <el-button type="primary" @click="submit">保存</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup>
import { listFences, createFence, setFenceEnabled } from '@/api/wear/fences'
import { peopleOptions } from '@/api/wear/people'
import useUserStore from '@/store/modules/user'

const userStore = useUserStore()
const { proxy } = getCurrentInstance()
const canEdit = computed(() => userStore.canEditFence)
const loading = ref(false)
const list = ref([])
const total = ref(0)
const queryParams = reactive({ current: 1, size: 10 })
const formOpen = ref(false)
const form = reactive({
  name: '',
  polygonText: '',
  debounceSeconds: '60',
  applyMode: 'all_site',
  personIds: [],
  timeStart: '',
  timeEnd: ''
})
const people = ref([])

function unwrap(res) {
  return res && res.data !== undefined ? res.data : res
}

function getList() {
  loading.value = true
  listFences(queryParams).then(res => {
    const page = unwrap(res) || {}
    list.value = page.records || []
    total.value = page.total || 0
  }).finally(() => { loading.value = false })
}

function openForm() {
  form.name = ''
  form.polygonText = '[{"lng":117.10,"lat":36.10},{"lng":117.14,"lat":36.10},{"lng":117.14,"lat":36.14},{"lng":117.10,"lat":36.14}]'
  form.debounceSeconds = '60'
  form.applyMode = 'all_site'
  form.personIds = []
  form.timeStart = ''
  form.timeEnd = ''
  peopleOptions().then(res => { people.value = unwrap(res) || [] }).catch(() => { people.value = [] })
  formOpen.value = true
}

function submit() {
  let polygon = []
  try {
    polygon = JSON.parse(form.polygonText)
  } catch (e) {
    proxy.$modal.msgError('多边形 JSON 无效')
    return
  }
  const body = {
    name: form.name,
    polygon,
    debounceSeconds: Number(form.debounceSeconds),
    applyMode: form.applyMode
  }
  if (form.applyMode === 'persons') {
    body.personIds = form.personIds
  }
  if (form.timeStart) body.timeStart = form.timeStart
  if (form.timeEnd) body.timeEnd = form.timeEnd
  createFence(body).then(() => {
    proxy.$modal.msgSuccess('已保存')
    formOpen.value = false
    getList()
  })
}

function toggle(row) {
  setFenceEnabled(row.id, { enabled: !row.enabled, version: row.version }).then(() => {
    proxy.$modal.msgSuccess(row.enabled ? '已禁用（历史事件保留）' : '已启用')
    getList()
  })
}

function onSiteChanged() {
  getList()
}

onMounted(() => {
  getList()
  window.addEventListener('site-changed', onSiteChanged)
})
onUnmounted(() => window.removeEventListener('site-changed', onSiteChanged))
</script>

<style scoped>
.w-180 { width: 180px; }
.w-140 { width: 140px; }
</style>
