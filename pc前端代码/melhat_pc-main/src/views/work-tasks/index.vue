<template>
  <div class="app-container">
    <ModuleHeader
      module="system"
      title="作业任务"
      description="任务不是工作票。无票显示待核实，不是违章。结束任务不会关闭事件。"
    />
    <el-form class="search-form" :inline="true" :model="queryParams">
      <el-form-item label="状态">
        <el-select v-model="queryParams.status" class="w-140" clearable placeholder="全部">
          <el-option label="草稿" value="draft" />
          <el-option label="就绪" value="ready" />
          <el-option label="进行中" value="in_progress" />
          <el-option label="已暂停" value="paused" />
          <el-option label="已结束" value="ended" />
        </el-select>
      </el-form-item>
      <el-form-item>
        <el-button type="primary" icon="Search" @click="handleQuery">搜索</el-button>
        <el-button v-if="canEdit" type="primary" icon="Plus" @click="openForm()">新建任务</el-button>
      </el-form-item>
    </el-form>
    <el-table v-loading="loading" class="custom-table" :data="list" highlight-current-row @row-click="openDetail">
      <template #empty><BrandedEmpty compact description="暂无任务" /></template>
      <el-table-column label="任务" prop="title" min-width="140" show-overflow-tooltip />
      <el-table-column align="center" label="类型" min-width="140">
        <template #default="scope">{{ workTypeLabel(scope.row.workType) }}</template>
      </el-table-column>
      <el-table-column align="center" label="状态" min-width="140">
        <template #default="scope">{{ taskStatusLabel(scope.row.status) }}</template>
      </el-table-column>
      <el-table-column align="center" label="票" min-width="140">
        <template #default="scope">
          <el-tag v-if="scope.row.ticketStatus === 'unverified'" type="warning" size="small">待核实</el-tag>
          <span v-else>{{ ticketStatusLabel(scope.row.ticketStatus) }}</span>
        </template>
      </el-table-column>
      <el-table-column align="center" label="标记" min-width="140">
        <template #default="scope"><el-tag v-if="scope.row.demo" type="warning" size="small">演示</el-tag></template>
      </el-table-column>
    </el-table>
    <pagination v-show="total > 0" v-model:page="queryParams.current" v-model:limit="queryParams.size" :total="total" @pagination="getList" />

    <el-dialog v-model="formOpen" title="新建任务" width="520px">
      <el-form label-width="100px">
        <el-form-item label="标题"><el-input v-model="form.title" /></el-form-item>
        <el-form-item label="类型">
          <el-select v-model="form.workType">
            <el-option label="巡检" value="patrol" />
            <el-option label="高处" value="height" />
            <el-option label="其他" value="other" />
          </el-select>
        </el-form-item>
        <el-form-item label="区域">
          <el-select v-model="form.spaceId" clearable>
            <el-option v-for="item in spaces" :key="item.id" :label="item.name" :value="item.id" />
          </el-select>
        </el-form-item>
        <el-form-item label="开始"><el-date-picker v-model="form.plannedStart" type="datetime" value-format="YYYY-MM-DDTHH:mm:ss+08:00" /></el-form-item>
        <el-form-item label="结束"><el-date-picker v-model="form.plannedEnd" type="datetime" value-format="YYYY-MM-DDTHH:mm:ss+08:00" /></el-form-item>
        <el-form-item label="成员">
          <el-select v-model="form.personIds" multiple filterable>
            <el-option v-for="p in people" :key="p.id" :label="p.name + ' ' + p.personCode" :value="p.id" />
          </el-select>
        </el-form-item>
        <el-form-item label="装备要求">
          <el-checkbox-group v-model="form.requirements">
            <el-checkbox label="helmet">安全帽</el-checkbox>
            <el-checkbox label="belt">安全带</el-checkbox>
          </el-checkbox-group>
        </el-form-item>
        <el-form-item label="要求票号"><el-switch v-model="form.ticketRequired" /></el-form-item>
        <el-form-item v-if="form.ticketRequired" label="票号"><el-input v-model="form.ticketNo" placeholder="空则待核实，不是违章" /></el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="formOpen = false">取消</el-button>
        <el-button type="primary" @click="submitForm">保存</el-button>
      </template>
    </el-dialog>

    <el-dialog v-model="detailOpen" title="任务详情" width="640px">
      <p>状态：{{ taskStatusLabel(detail.status) }}　类型：{{ workTypeLabel(detail.workType) }}
        <el-tag v-if="detail.demo" type="warning" size="small" class="ml8">演示</el-tag>
      </p>
      <p>区域：{{ detail.spaceName || '-' }}　票：{{ ticketStatusLabel(detail.ticketStatus) }} {{ detail.ticketNo || '' }}</p>
      <p>计划：{{ detail.plannedStart || '-' }} ~ {{ detail.plannedEnd || '-' }}</p>
      <p>成员：<span v-for="m in (detail.members || [])" :key="m.personId">{{ m.name }} {{ m.personCode }}；</span><span v-if="!(detail.members && detail.members.length)">无</span></p>
      <p>装备检查：</p>
      <p v-for="(item, idx) in (detail.equipmentCheck || [])" :key="idx">
        {{ item.personName }} {{ item.typeCode === 'belt' ? '安全带' : '安全帽' }}
        {{ equipmentResultLabel(item.result) }}
        {{ item.sn || '' }}
        <el-tag v-if="item.needsConfirm" type="warning" size="small">待人工确认</el-tag>
      </p>
      <p v-if="!(detail.equipmentCheck && detail.equipmentCheck.length)">无装备要求。</p>
      <p>关联事件：</p>
      <p v-for="ev in taskEvents" :key="ev.id">{{ eventTypeLabel(ev.type) }} {{ eventStatusLabel(ev.status) }} {{ ev.personName }}</p>
      <p v-if="detail.status === 'draft'" class="hint">草稿需补齐计划时间和成员后才会变为就绪，才能开始。</p>
      <div v-if="canEdit" class="detail-actions">
        <el-button v-if="detail.status === 'draft' || detail.status === 'ready'" @click="openEdit">补齐/编辑</el-button>
        <el-button v-if="detail.status === 'ready' || detail.status === 'paused'" type="primary" @click="doStart">开始</el-button>
        <el-button v-if="detail.status === 'in_progress'" @click="doPause">暂停</el-button>
        <el-button v-if="detail.status === 'in_progress' || detail.status === 'paused' || detail.status === 'ready'" type="danger" @click="doEnd">结束</el-button>
      </div>
    </el-dialog>

    <el-dialog v-model="editOpen" title="补齐任务" width="520px">
      <el-form label-width="100px">
        <el-form-item label="开始"><el-date-picker v-model="editForm.plannedStart" type="datetime" value-format="YYYY-MM-DDTHH:mm:ss+08:00" /></el-form-item>
        <el-form-item label="结束"><el-date-picker v-model="editForm.plannedEnd" type="datetime" value-format="YYYY-MM-DDTHH:mm:ss+08:00" /></el-form-item>
        <el-form-item label="成员">
          <el-select v-model="editForm.personIds" multiple filterable>
            <el-option v-for="p in people" :key="p.id" :label="p.name + ' ' + p.personCode" :value="p.id" />
          </el-select>
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="editOpen = false">取消</el-button>
        <el-button type="primary" @click="submitEdit">保存</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup>
import {
  listWorkTasks, getWorkTask, createWorkTask, updateWorkTask, addWorkTaskMembers, startWorkTask, pauseWorkTask, endWorkTask, listWorkTaskEvents,
  workTypeLabel, taskStatusLabel, ticketStatusLabel, equipmentResultLabel
} from '@/api/wear/tasks'
import { peopleOptions, listSpaces } from '@/api/wear/people'
import { eventTypeLabel, eventStatusLabel } from '@/api/wear/events'
import useUserStore from '@/store/modules/user'

const userStore = useUserStore()
const route = useRoute()
const { proxy } = getCurrentInstance()
const canEdit = computed(() => userStore.canEditTask)
const loading = ref(false)
const list = ref([])
const total = ref(0)
const queryParams = reactive({ current: 1, size: 10, status: '' })
const formOpen = ref(false)
const detailOpen = ref(false)
const detail = ref({})
const taskEvents = ref([])
const people = ref([])
const spaces = ref([])
const form = reactive({
  title: '', workType: 'patrol', spaceId: '', plannedStart: '', plannedEnd: '',
  personIds: [], requirements: ['helmet'], ticketRequired: false, ticketNo: ''
})
const editOpen = ref(false)
const editForm = reactive({ plannedStart: '', plannedEnd: '', personIds: [] })

function unwrap(res) {
  return res && res.data !== undefined ? res.data : res
}

function getList() {
  loading.value = true
  listWorkTasks(queryParams).then(res => {
    const page = unwrap(res) || {}
    list.value = page.records || []
    total.value = page.total || 0
  }).finally(() => { loading.value = false })
}

function handleQuery() {
  queryParams.current = 1
  getList()
}

function openForm() {
  peopleOptions().then(res => { people.value = unwrap(res) || [] })
  listSpaces().then(res => { spaces.value = unwrap(res) || [] })
  Object.assign(form, { title: '', workType: 'patrol', spaceId: '', plannedStart: '', plannedEnd: '', personIds: [], requirements: ['helmet'], ticketRequired: false, ticketNo: '' })
  formOpen.value = true
}

function submitForm() {
  createWorkTask({ ...form }).then(() => {
    proxy.$modal.msgSuccess('已保存')
    formOpen.value = false
    getList()
  })
}

function openDetail(row) {
  getWorkTask(row.id).then(res => {
    detail.value = unwrap(res) || row
    detailOpen.value = true
  })
  listWorkTaskEvents(row.id).then(res => { taskEvents.value = unwrap(res) || [] }).catch(() => { taskEvents.value = [] })
}

function doStart() {
  startWorkTask(detail.value.id, { version: detail.value.version }).then(() => {
    proxy.$modal.msgSuccess('已开始')
    openDetail(detail.value)
    getList()
  })
}

function doPause() {
  pauseWorkTask(detail.value.id, { version: detail.value.version }).then(() => {
    proxy.$modal.msgSuccess('已暂停')
    openDetail(detail.value)
    getList()
  })
}

function openHighRisk() {
  return (taskEvents.value || []).some(ev => ev.severity === 'high' && ev.status && ev.status !== 'closed')
}

function doEnd() {
  const ack = openHighRisk()
  const run = () => endWorkTask(detail.value.id, { version: detail.value.version, acknowledgeOpenHighRisk: ack }).then(() => {
    proxy.$modal.msgSuccess('任务已结束，关联事件未关闭')
    openDetail(detail.value)
    getList()
  })
  if (ack) {
    proxy.$modal.confirm('存在未关闭的高风险事件。结束任务不会关闭这些事件。确认结束？').then(run).catch(() => {})
  } else {
    run()
  }
}

function openEdit() {
  peopleOptions().then(res => { people.value = unwrap(res) || [] })
  editForm.plannedStart = detail.value.plannedStart || ''
  editForm.plannedEnd = detail.value.plannedEnd || ''
  editForm.personIds = (detail.value.members || []).map(m => m.personId)
  editOpen.value = true
}

function submitEdit() {
  updateWorkTask(detail.value.id, {
    version: detail.value.version,
    plannedStart: editForm.plannedStart,
    plannedEnd: editForm.plannedEnd
  }).then(res => {
    const updated = unwrap(res) || detail.value
    const existing = (updated.members || []).map(m => String(m.personId))
    const extra = (editForm.personIds || []).filter(id => existing.indexOf(String(id)) === -1)
    const after = extra.length
      ? addWorkTaskMembers(detail.value.id, { personIds: extra })
      : Promise.resolve()
    return after
  }).then(() => {
    editOpen.value = false
    proxy.$modal.msgSuccess('已保存')
    openDetail(detail.value)
    getList()
  })
}

function onSiteChanged() {
  detailOpen.value = false
  getList()
}

onMounted(() => {
  getList()
  if (route.query.id) {
    openDetail({ id: route.query.id })
  }
  window.addEventListener('site-changed', onSiteChanged)
})
watch(() => route.query.id, (id) => {
  if (id) openDetail({ id })
})
onUnmounted(() => window.removeEventListener('site-changed', onSiteChanged))
</script>

<style scoped>
.w-140 { width: 140px; }
.ml8 { margin-left: 8px; }
.detail-actions { margin-top: 12px; display: flex; flex-wrap: wrap; gap: 8px; }
.hint { color: #64748b; font-size: 13px; }
</style>
