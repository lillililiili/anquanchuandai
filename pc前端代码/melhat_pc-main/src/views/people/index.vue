<template>
  <div class="app-container">
    <ModuleHeader module="system" title="人员" description="现场人员独立于登录账号。停用不删除历史。详情可查看当前装备。" />
    <el-form class="search-form" :inline="true" :model="queryParams">
      <el-form-item label="姓名">
        <el-input v-model="queryParams.name" class="w-180" clearable placeholder="姓名" @keyup.enter="handleQuery" />
      </el-form-item>
      <el-form-item label="人员标识">
        <el-input v-model="queryParams.personCode" class="w-180" clearable placeholder="工号" @keyup.enter="handleQuery" />
      </el-form-item>
      <el-form-item label="班组">
        <el-select v-model="queryParams.teamId" class="w-140" clearable placeholder="全部">
          <el-option v-for="item in teams" :key="item.id" :label="item.name" :value="item.id" />
        </el-select>
      </el-form-item>
      <el-form-item label="承包商">
        <el-select v-model="queryParams.contractorId" class="w-140" clearable placeholder="全部">
          <el-option v-for="item in contractors" :key="item.id" :label="item.name" :value="item.id" />
        </el-select>
      </el-form-item>
      <el-form-item label="状态">
        <el-select v-model="queryParams.status" class="w-140" clearable placeholder="全部">
          <el-option label="在职" value="0" />
          <el-option label="停用" value="1" />
        </el-select>
      </el-form-item>
      <el-form-item>
        <el-button type="primary" icon="Search" @click="handleQuery">搜索</el-button>
        <el-button icon="Refresh" @click="resetQuery">重置</el-button>
      </el-form-item>
    </el-form>
    <el-row class="mb8">
      <el-button v-if="canWrite" type="primary" icon="Plus" @click="openForm()">新增人员</el-button>
      <el-button v-if="canWrite" icon="Upload" @click="importOpen = true">批量导入</el-button>
      <el-button icon="Download" @click="downloadExport('people', { ...queryParams }, '人员台账.xlsx')">导出</el-button>
    </el-row>
    <el-table v-loading="loading" class="custom-table" :data="list">
      <template #empty><BrandedEmpty compact description="暂无人员" /></template>
      <el-table-column label="人员标识" prop="personCode" />
      <el-table-column label="姓名" prop="name" />
      <el-table-column label="班组" prop="teamName" />
      <el-table-column label="承包商" prop="contractorName" />
      <el-table-column label="登录账号" width="120">
        <template #default="scope">{{ scope.row.accountUserId ? '已关联' : '无账号' }}</template>
      </el-table-column>
      <el-table-column label="有效期" width="180">
        <template #default="scope">
          <span>{{ validityText(scope.row) }}</span>
          <el-tag v-if="validityHint(scope.row)" class="ml8" type="warning" size="small">{{ validityHint(scope.row) }}</el-tag>
        </template>
      </el-table-column>
      <el-table-column label="状态" width="100">
        <template #default="scope">{{ scope.row.status === '1' ? '停用' : '在职' }}</template>
      </el-table-column>
      <el-table-column label="可选" width="80">
        <template #default="scope">{{ scope.row.selectable ? '是' : '否' }}</template>
      </el-table-column>
      <el-table-column label="操作" width="200">
        <template #default="scope">
          <el-button link type="primary" @click="openDetail(scope.row)">详情</el-button>
          <el-button v-if="canWrite" link type="primary" @click="openForm(scope.row)">编辑</el-button>
          <el-button v-if="canWrite && scope.row.status === '0'" link type="danger" @click="disableRow(scope.row)">停用</el-button>
          <el-button v-if="canWrite && scope.row.status === '1'" link type="success" @click="enableRow(scope.row)">恢复</el-button>
        </template>
      </el-table-column>
    </el-table>
    <pagination v-show="total > 0" v-model:page="queryParams.current" v-model:limit="queryParams.size" :total="total" @pagination="getList" />

    <el-dialog v-model="formOpen" :title="form.id ? '编辑人员' : '新增人员'" width="560px">
      <el-form label-width="100px" :model="form">
        <el-form-item label="人员标识"><el-input v-model="form.personCode" :disabled="!!form.id" /></el-form-item>
        <el-form-item label="姓名"><el-input v-model="form.name" /></el-form-item>
        <el-form-item label="班组">
          <el-select v-model="form.teamId" clearable placeholder="可选">
            <el-option v-for="item in teams" :key="item.id" :label="item.name" :value="item.id" />
          </el-select>
        </el-form-item>
        <el-form-item label="承包商">
          <el-select v-model="form.contractorId" clearable placeholder="可选">
            <el-option v-for="item in contractors" :key="item.id" :label="item.name" :value="item.id" />
          </el-select>
        </el-form-item>
        <el-form-item label="登录账号ID"><el-input v-model="form.accountUserId" placeholder="可空。无账号也能作为现场人员" /></el-form-item>
        <el-form-item label="有效期从"><el-date-picker v-model="form.validFrom" type="date" value-format="YYYY-MM-DD" placeholder="不限" /></el-form-item>
        <el-form-item label="有效期至"><el-date-picker v-model="form.validTo" type="date" value-format="YYYY-MM-DD" placeholder="不限" /></el-form-item>
        <el-form-item label="授权厂站"><el-select v-model="form.siteIds" multiple collapse-tags placeholder="至少选择一个厂站"><el-option v-for="site in userStore.sites" :key="site.id" :label="site.name" :value="String(site.id)" /></el-select></el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="formOpen = false">取消</el-button>
        <el-button type="primary" @click="submitForm">保存</el-button>
      </template>
    </el-dialog>

    <el-dialog v-model="detailOpen" title="人员详情" width="640px">
      <p>标识：{{ detail.personCode }}　姓名：{{ detail.name }}　ID：{{ detail.id }}</p>
      <p>账号：{{ detail.accountUserId || '无' }}　状态：{{ detail.status === '1' ? '停用' : '在职' }}　可选：{{ detail.selectable ? '是' : '否' }}</p>
      <p>有效期：{{ detail.validFrom || '不限' }} ~ {{ detail.validTo || '不限' }}
        <el-tag v-if="validityHint(detail)" class="ml8" type="warning" size="small">{{ validityHint(detail) }}</el-tag>
      </p>
      <p>班组：{{ detail.teamName || '-' }}　承包商：{{ detail.contractorName || '-' }}</p>
      <el-divider />
      <p>当前装备：</p>
      <p v-if="!(detail.equipment && detail.equipment.length)">无在用设备</p>
      <p v-for="item in (detail.equipment || [])" :key="item.id">{{ item.typeCode === 'belt' ? '安全带' : '安全帽' }} {{ item.sn }}　{{ item.issuedAt }}</p>
      <p v-if="personHistory.length">领用历史：</p>
      <p v-for="item in personHistory" :key="'h-' + item.id">{{ item.sn }} {{ item.issuedAt }} → {{ item.returnedAt || '在用' }}</p>
    </el-dialog>
    <LedgerImportDialog v-model="importOpen" resource="people" template-name="人员导入模板.xlsx" @success="getList" />
  </div>
</template>

<script setup>
import { listPeople, getPerson, createPerson, updatePerson, changePersonStatus, listTeams, listContractors } from '@/api/wear/people'
import { listPersonAssignments } from '@/api/wear/assignments'
import useUserStore from '@/store/modules/user'
import { ElMessageBox } from 'element-plus'
import { downloadExport } from '@/api/wear/admin'
import LedgerImportDialog from '@/components/LedgerImportDialog/index.vue'

const userStore = useUserStore()
const { proxy } = getCurrentInstance()
const canWrite = computed(() => userStore.canWritePerson)
const loading = ref(false)
const list = ref([])
const total = ref(0)
const queryParams = reactive({ current: 1, size: 10, name: '', personCode: '', status: '', teamId: '', contractorId: '' })
const formOpen = ref(false)
const detailOpen = ref(false)
const form = reactive({ id: null, personCode: '', name: '', teamId: '', contractorId: '', accountUserId: '', validFrom: null, validTo: null, siteIds: [], version: 1 })
const detail = ref({})
const personHistory = ref([])
const teams = ref([])
const contractors = ref([])
const importOpen = ref(false)

function unwrap(res) {
  return res && res.data !== undefined ? res.data : res
}

function getList() {
  loading.value = true
  listPeople(queryParams).then(res => {
    const page = unwrap(res) || {}
    list.value = page.records || []
    total.value = page.total || 0
  }).finally(() => { loading.value = false })
}

function handleQuery() {
  queryParams.current = 1
  getList()
}

function resetQuery() {
  queryParams.name = ''
  queryParams.personCode = ''
  queryParams.status = ''
  queryParams.teamId = ''
  queryParams.contractorId = ''
  handleQuery()
}

function validityText(row) {
  if (!row) return '不限'
  const from = row.validFrom || '不限'
  const to = row.validTo || '不限'
  if (from === '不限' && to === '不限') return '不限'
  return from + ' ~ ' + to
}

function validityHint(row) {
  if (!row || row.status === '1') return ''
  if (row.selectable) return ''
  const today = new Date().toISOString().slice(0, 10)
  if (row.validTo && row.validTo < today) return '有效期已过'
  if (row.validFrom && row.validFrom > today) return '尚未生效'
  return row.status === '0' ? '当前厂站不可选' : ''
}

function loadCatalog() {
  listTeams().then(res => { teams.value = unwrap(res) || [] })
  listContractors().then(res => { contractors.value = unwrap(res) || [] })
}

function openForm(row) {
  loadCatalog()
  if (row) {
    Object.assign(form, { id: row.id, personCode: row.personCode, name: row.name, teamId: row.teamId || '', contractorId: row.contractorId || '', accountUserId: row.accountUserId || '', validFrom: row.validFrom, validTo: row.validTo, siteIds: (row.siteIds || []).map(String), version: row.version })
  } else {
    Object.assign(form, { id: null, personCode: '', name: '', teamId: '', contractorId: '', accountUserId: '', validFrom: null, validTo: null, siteIds: userStore.currentSiteId ? [String(userStore.currentSiteId)] : [], version: 1 })
  }
  formOpen.value = true
}

function openDetail(row) {
  getPerson(row.id).then(res => {
    detail.value = unwrap(res) || row
    detailOpen.value = true
  })
  listPersonAssignments(row.id).then(res => { personHistory.value = unwrap(res) || [] }).catch(() => { personHistory.value = [] })
}

function submitForm() {
  const payload = { ...form }
  const req = form.id ? updatePerson(form.id, payload) : createPerson(payload)
  req.then(() => {
    proxy.$modal.msgSuccess('保存成功')
    formOpen.value = false
    getList()
  })
}

function disableRow(row) {
  ElMessageBox.confirm('停用后不可再领用或加入新任务，历史资料保留。确认停用？', '停用确认', { type: 'warning' })
    .then(() => changePersonStatus(row.id, { status: '1', version: row.version }))
    .then(() => { proxy.$modal.msgSuccess('已停用'); getList() })
    .catch(() => {})
}

function enableRow(row) {
  changePersonStatus(row.id, { status: '0', version: row.version }).then(() => {
    proxy.$modal.msgSuccess('已恢复')
    getList()
  })
}

function onSiteChanged() {
  loadCatalog()
  getList()
}
onMounted(() => {
  getList()
  loadCatalog()
  window.addEventListener('site-changed', onSiteChanged)
})
onUnmounted(() => window.removeEventListener('site-changed', onSiteChanged))
</script>

<style scoped>
.detail-actions { margin-top: 8px; display: flex; flex-wrap: wrap; gap: 8px; }
</style>
