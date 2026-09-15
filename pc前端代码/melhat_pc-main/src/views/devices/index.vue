<template>
  <div class="app-container">
    <ModuleHeader module="system" title="设备台账" description="帽和带共用台账。在库可领用，已领用可归还。连接状态未知不是在线。" />
    <el-form class="search-form" :inline="true" :model="queryParams">
      <el-form-item label="类型">
        <el-select v-model="queryParams.typeCode" class="w-140" clearable placeholder="全部">
          <el-option label="安全帽" value="helmet" />
          <el-option label="安全带" value="belt" />
        </el-select>
      </el-form-item>
      <el-form-item label="型号">
        <el-select v-model="queryParams.modelId" class="w-180" clearable placeholder="全部">
          <el-option v-for="item in models" :key="item.id" :label="item.name" :value="item.id" />
        </el-select>
      </el-form-item>
      <el-form-item label="序列号">
        <el-input v-model="queryParams.sn" class="w-180" clearable placeholder="SN" @keyup.enter="handleQuery" />
      </el-form-item>
      <el-form-item label="资产状态">
        <el-select v-model="queryParams.assetStatus" class="w-140" clearable placeholder="全部">
          <el-option label="未分配" value="unassigned" />
          <el-option label="在库" value="in_stock" />
          <el-option label="已领用" value="issued" />
          <el-option label="维修" value="maintenance" />
          <el-option label="停用" value="disabled" />
          <el-option label="报废" value="scrapped" />
        </el-select>
      </el-form-item>
      <el-form-item>
        <el-button type="primary" icon="Search" @click="handleQuery">搜索</el-button>
        <el-button icon="Refresh" @click="resetQuery">重置</el-button>
      </el-form-item>
    </el-form>
    <el-row class="mb8">
      <el-button v-if="canWrite" type="primary" icon="Plus" @click="openForm()">登记设备</el-button>
      <el-button v-if="canWrite" icon="Upload" @click="importOpen = true">批量导入</el-button>
      <el-button icon="Download" @click="downloadExport('devices', { ...queryParams }, '设备台账.xlsx')">导出</el-button>
    </el-row>
    <el-table v-loading="loading" class="custom-table" :data="list">
      <template #empty><BrandedEmpty compact description="暂无设备" /></template>
      <el-table-column label="类型" width="90">
        <template #default="scope">{{ typeLabel(scope.row.typeCode) }}</template>
      </el-table-column>
      <el-table-column label="序列号" prop="sn" />
      <el-table-column label="型号" prop="modelName" />
      <el-table-column label="厂站" prop="siteName" width="140">
        <template #default="scope">{{ scope.row.siteName || '未分配' }}</template>
      </el-table-column>
      <el-table-column label="资产状态" width="100">
        <template #default="scope">{{ assetLabel(scope.row.assetStatus) }}</template>
      </el-table-column>
      <el-table-column label="连接" width="90">
        <template #default="scope">{{ connectionLabel(scope.row) }}</template>
      </el-table-column>
      <el-table-column label="操作" width="280">
        <template #default="scope">
          <el-button link type="primary" @click="openDetail(scope.row)">详情</el-button>
          <el-button v-if="canWrite" link type="primary" @click="openForm(scope.row)">编辑</el-button>
          <el-button v-if="canWrite && scope.row.assetStatus === 'in_stock'" link type="primary" @click="openIssue(scope.row)">领用</el-button>
          <el-button v-if="canWrite && scope.row.assetStatus === 'issued'" link type="primary" @click="openReturn(scope.row)">归还</el-button>
          <el-button v-if="canWrite" link type="primary" @click="openSite(scope.row)">分配厂站</el-button>
        </template>
      </el-table-column>
    </el-table>
    <pagination v-show="total > 0" v-model:page="queryParams.current" v-model:limit="queryParams.size" :total="total" @pagination="getList" />

    <el-dialog v-model="formOpen" :title="form.id ? '编辑设备' : '登记设备'" width="520px">
      <el-form label-width="100px" :model="form">
        <el-form-item label="厂商"><el-input v-model="form.manufacturerCode" :disabled="!!form.id" /></el-form-item>
        <el-form-item label="序列号"><el-input v-model="form.sn" :disabled="!!form.id" /></el-form-item>
        <el-form-item label="型号">
          <el-select v-model="form.modelId" placeholder="选择型号">
            <el-option v-for="item in models" :key="item.id" :label="item.name + ' (' + item.modelCode + ')'" :value="item.id" />
          </el-select>
        </el-form-item>
        <el-form-item label="外部标识"><el-input v-model="form.externalCode" placeholder="帽号等厂商标识，可空" /></el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="formOpen = false">取消</el-button>
        <el-button type="primary" @click="submitForm">保存</el-button>
      </template>
    </el-dialog>

    <el-dialog v-model="siteOpen" title="分配厂站" width="420px">
      <el-form label-width="80px">
        <el-form-item label="厂站">
          <el-select v-model="siteForm.siteId" clearable placeholder="空=撤销分配">
            <el-option v-for="site in userStore.sites" :key="site.id" :label="site.name" :value="site.id" />
          </el-select>
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="siteOpen = false">取消</el-button>
        <el-button type="primary" @click="submitSite">保存</el-button>
      </template>
    </el-dialog>

    <el-dialog v-model="detailOpen" title="设备详情" width="640px">
      <p>ID：{{ detail.id }}　SN：{{ detail.sn }}　厂商：{{ detail.manufacturerCode }}</p>
      <p>类型：{{ typeLabel(detail.typeCode) }}　型号：{{ detail.modelName }}（{{ detail.modelCode }}）</p>
      <p>厂站：{{ detail.siteName || '未分配' }}　资产：{{ assetLabel(detail.assetStatus) }}</p>
      <p>连接：{{ connectionLabel(detail) }}　电量：{{ detail.battery == null ? '未知' : detail.battery }}　最后上报：{{ detail.lastReportedAt || '未知' }}</p>
      <p>位置质量：{{ detail.locationQuality || 'unknown' }}　数据来源：{{ detail.source || 'db' }}<span v-if="detail.demo">　演示数据</span></p>
      <p>旧帽映射：{{ detail.legacyHatId || '无' }}</p>
      <el-divider />
      <p>能力（型号）：属性 {{ capList(detail, 'attributes') }}；事件 {{ capList(detail, 'events') }}；操作 {{ capList(detail, 'actions') }}</p>
      <p v-if="supportsCapability(detail, 'video')">本型号支持视频。</p>
      <p v-else>本型号无视频能力，不提供视频入口。</p>
      <el-divider />
      <p>当前领用：<span v-if="detail.currentAssignment">{{ detail.currentAssignment.personName }}（{{ detail.currentAssignment.personCode }}） {{ detail.currentAssignment.issuedAt }}</span><span v-else>无</span></p>
      <p v-if="history.length">历史：</p>
      <p v-for="item in history" :key="item.id">{{ item.issuedAt }} {{ item.personName }} {{ item.returnedAt ? '已还 ' + (item.returnKind || '') : '在用' }}</p>
      <el-divider />
      <p>最近样本：</p>
      <p v-for="item in samples" :key="item.id">{{ item.occurredAt }} {{ item.lat || '-' }}, {{ item.lng || '-' }} {{ item.locationQuality }}</p>
      <p v-if="!samples.length">无遥测样本。</p>
      <p v-if="ingestRows.length">接入摘要：</p>
      <p v-for="item in ingestRows" :key="item.id">{{ item.receivedAt }} {{ item.path }} {{ item.processStatus }}</p>
    </el-dialog>

    <el-dialog v-model="issueOpen" title="领用" width="460px">
      <el-form label-width="80px">
        <el-form-item label="人员">
          <el-select v-model="issueForm.personId" filterable placeholder="仅可选人员">
            <el-option v-for="p in peopleOptions" :key="p.id" :label="p.name + ' ' + p.personCode" :value="p.id" />
          </el-select>
        </el-form-item>
      </el-form>
      <p class="el-text el-text--info">不可选人员不会出现。超时请刷新当前领用，勿重复点击。</p>
      <template #footer>
        <el-button @click="issueOpen = false">取消</el-button>
        <el-button type="primary" @click="submitIssue">确认领用</el-button>
      </template>
    </el-dialog>

    <el-dialog v-model="returnOpen" title="归还" width="420px">
      <el-form label-width="80px">
        <el-form-item label="原因"><el-input v-model="returnForm.reason" placeholder="可选" /></el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="returnOpen = false">取消</el-button>
        <el-button type="primary" @click="submitReturn">确认归还</el-button>
      </template>
    </el-dialog>
    <LedgerImportDialog v-model="importOpen" resource="devices" template-name="设备导入模板.xlsx" @success="getList" />
  </div>
</template>

<script setup>
import { listDevices, getDevice, createDevice, updateDevice, assignDeviceSite, listProductModels, supportsCapability, connectionLabel, listDeviceSamples, listDeviceIngest } from '@/api/wear/devices'
import { issueAssignment, returnAssignment, listDeviceAssignments, newIdempotencyKey } from '@/api/wear/assignments'
import { peopleOptions as fetchPeopleOptions } from '@/api/wear/people'
import useUserStore from '@/store/modules/user'
import { downloadExport } from '@/api/wear/admin'
import LedgerImportDialog from '@/components/LedgerImportDialog/index.vue'

const userStore = useUserStore()
const { proxy } = getCurrentInstance()
const canWrite = computed(() => userStore.canWriteDevice)
const loading = ref(false)
const list = ref([])
const total = ref(0)
const models = ref([])
const queryParams = reactive({ current: 1, size: 10, typeCode: '', modelId: '', sn: '', assetStatus: '' })
const formOpen = ref(false)
const detailOpen = ref(false)
const siteOpen = ref(false)
const issueOpen = ref(false)
const returnOpen = ref(false)
const form = reactive({ id: null, manufacturerCode: 'MELHAT', sn: '', modelId: '', externalCode: '', version: 1 })
const siteForm = reactive({ id: null, siteId: '', version: 1 })
const issueForm = reactive({ deviceId: '', personId: '', key: '' })
const returnForm = reactive({ assignmentId: '', reason: '', key: '' })
const detail = ref({})
const history = ref([])
const samples = ref([])
const ingestRows = ref([])
const peopleOptions = ref([])
const importOpen = ref(false)

function unwrap(res) {
  return res && res.data !== undefined ? res.data : res
}

function typeLabel(code) {
  if (code === 'belt') return '安全带'
  if (code === 'helmet') return '安全帽'
  return code || '-'
}

function assetLabel(status) {
  const map = { unassigned: '未分配', in_stock: '在库', issued: '已领用', maintenance: '维修', disabled: '停用', scrapped: '报废' }
  return map[status] || status || '-'
}

function capList(row, key) {
  const caps = (row && row.capabilities) || {}
  const items = caps[key] || []
  return items.length ? items.join('、') : '无'
}

function getList() {
  loading.value = true
  listDevices(queryParams).then(res => {
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
  queryParams.typeCode = ''
  queryParams.modelId = ''
  queryParams.sn = ''
  queryParams.assetStatus = ''
  handleQuery()
}

function loadModels() {
  listProductModels().then(res => { models.value = unwrap(res) || [] })
}

function openForm(row) {
  loadModels()
  if (row) {
    Object.assign(form, { id: row.id, manufacturerCode: row.manufacturerCode, sn: row.sn, modelId: row.modelId || '', externalCode: row.externalCode || '', version: row.version })
  } else {
    Object.assign(form, { id: null, manufacturerCode: 'MELHAT', sn: '', modelId: '', externalCode: '', version: 1 })
  }
  formOpen.value = true
}

function openDetail(row) {
  getDevice(row.id).then(res => {
    detail.value = unwrap(res) || row
    detailOpen.value = true
  })
  listDeviceAssignments(row.id).then(res => { history.value = unwrap(res) || [] }).catch(() => { history.value = [] })
  listDeviceSamples(row.id).then(res => { samples.value = unwrap(res) || [] }).catch(() => { samples.value = [] })
  listDeviceIngest(row.id).then(res => { ingestRows.value = unwrap(res) || [] }).catch(() => { ingestRows.value = [] })
}

function openIssue(row) {
  issueForm.deviceId = row.id
  issueForm.personId = ''
  issueForm.key = newIdempotencyKey()
  fetchPeopleOptions().then(res => { peopleOptions.value = unwrap(res) || [] })
  issueOpen.value = true
}

function openReturn(row) {
  getDevice(row.id).then(res => {
    const d = unwrap(res) || {}
    const asg = d.currentAssignment
    if (!asg || !asg.id) {
      proxy.$modal.msgError('没有有效领用，请刷新')
      getList()
      return
    }
    returnForm.assignmentId = asg.id
    returnForm.reason = ''
    returnForm.key = newIdempotencyKey()
    returnOpen.value = true
  }).catch(() => {
    proxy.$modal.msgError('结果待核验，请刷新后再试')
  })
}

function submitIssue() {
  issueAssignment({ deviceId: issueForm.deviceId, personId: issueForm.personId, idempotencyKey: issueForm.key }).then(() => {
    proxy.$modal.msgSuccess('领用成功')
    issueOpen.value = false
    getList()
  }).catch(() => {
    proxy.$modal.msgError('结果待核验，请刷新当前领用后再决定是否重试')
    getList()
  })
}

function submitReturn() {
  returnAssignment(returnForm.assignmentId, { reason: returnForm.reason, idempotencyKey: returnForm.key }).then(() => {
    proxy.$modal.msgSuccess('已归还')
    returnOpen.value = false
    getList()
  }).catch(() => {
    proxy.$modal.msgError('结果待核验，请刷新当前领用后再决定是否重试')
    getList()
  })
}

function openSite(row) {
  siteForm.id = row.id
  siteForm.siteId = row.siteId || ''
  siteForm.version = row.version
  siteOpen.value = true
}

function submitForm() {
  const payload = { ...form }
  const req = form.id ? updateDevice(form.id, payload) : createDevice(payload)
  req.then(() => {
    proxy.$modal.msgSuccess('保存成功')
    formOpen.value = false
    getList()
  })
}

function submitSite() {
  assignDeviceSite(siteForm.id, { siteId: siteForm.siteId || null, version: siteForm.version }).then(() => {
    proxy.$modal.msgSuccess('已更新厂站')
    siteOpen.value = false
    getList()
  })
}

function onSiteChanged() { getList() }
onMounted(() => {
  getList()
  loadModels()
  window.addEventListener('site-changed', onSiteChanged)
})
onUnmounted(() => window.removeEventListener('site-changed', onSiteChanged))
</script>
