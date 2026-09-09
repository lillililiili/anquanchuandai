<template>
  <div class="app-container">
    <ModuleHeader
      module="system"
      title="值班台"
      description="上班从这里开始。待办按当前厂站聚合。人数与设备数分开统计。交接须对方确认后才改责任。"
    />
    <el-alert
      v-if="!hasSite"
      class="mb8"
      title="请先在右上角选择厂站。值班数据按厂站隔离，未选厂站不会加载。"
      type="warning"
      show-icon
      :closable="false"
    />
    <ol class="flow">
      <li>先看待认领 / 已升级，点进<strong>安全事件</strong>认领，需要时再联系或播报。</li>
      <li>进行中作业看<strong>作业任务</strong>。无票是待核实，不是违章。安全带检查只能是未知。</li>
      <li>找人用<strong>人员位置</strong>（只信安全帽 GNSS）。围栏规则由设备管理员维护。</li>
      <li>主数据在<strong>人员</strong>、<strong>设备台账</strong>。旧版安全帽页不要当真相。</li>
    </ol>
    <el-row :gutter="12" class="stat-row">
      <el-col :xs="12" :sm="8" :md="4"><div class="stat" @click="goEvents({ status: 'open' })"><b>{{ summary.unclaimed || 0 }}</b><span>待认领</span></div></el-col>
      <el-col :xs="12" :sm="8" :md="4"><div class="stat" @click="goMine"><b>{{ summary.mine || 0 }}</b><span>我的处置</span></div></el-col>
      <el-col :xs="12" :sm="8" :md="4"><div class="stat warn" @click="goEvents({ escalated: 'true' })"><b>{{ summary.overdue || 0 }}</b><span>已升级</span></div></el-col>
      <el-col :xs="12" :sm="8" :md="4"><div class="stat warn" @click="goLost"><b>{{ summary.lostSupervision || 0 }}</b><span>失去监护</span></div></el-col>
      <el-col :xs="12" :sm="8" :md="4"><div class="stat"><b>{{ summary.peopleCount || 0 }}</b><span>在用人数</span></div></el-col>
      <el-col :xs="12" :sm="8" :md="4"><div class="stat"><b>{{ summary.deviceCount || 0 }}</b><span>在用设备</span></div></el-col>
    </el-row>
    <p class="hint">一人可同时持帽和带，故人数不必等于设备数。失去监护只统计进行中任务里安全帽未有效；安全带无协议，不计入。</p>

    <el-row :gutter="16">
      <el-col :xs="24" :md="12">
        <h3>进行中任务</h3>
        <el-table class="custom-table" :data="summary.activeTasks || []" @row-click="openTask">
          <template #empty><BrandedEmpty compact description="暂无进行中任务" /></template>
          <el-table-column label="任务" prop="title" />
          <el-table-column label="状态" width="90">
            <template #default="scope">{{ taskStatusLabel(scope.row.status) }}</template>
          </el-table-column>
          <el-table-column label="票" width="90">
            <template #default="scope">{{ ticketStatusLabel(scope.row.ticketStatus) }}</template>
          </el-table-column>
        </el-table>
        <el-button class="mt8" @click="$router.push('/business/work-tasks')">全部任务</el-button>
      </el-col>
      <el-col :xs="24" :md="12">
        <h3>未关闭事件</h3>
        <el-table class="custom-table" :data="summary.recentEvents || []" @row-click="openEvent">
          <template #empty><BrandedEmpty compact description="暂无事件" /></template>
          <el-table-column label="类型" width="88">
            <template #default="scope">{{ eventTypeLabel(scope.row.type) }}</template>
          </el-table-column>
          <el-table-column label="状态" width="90">
            <template #default="scope">{{ eventStatusLabel(scope.row.status) }}</template>
          </el-table-column>
          <el-table-column label="人员" prop="personName" />
        </el-table>
      </el-col>
    </el-row>

    <h3>交接班</h3>
    <el-form v-if="canEdit" :inline="true">
      <el-form-item label="接班人">
        <el-select v-model="handoverTo" class="w-180" filterable placeholder="选择值班/班组长">
          <el-option
            v-for="op in operators"
            :key="op.userId"
            :label="(op.nickName || op.userName) + ' (' + op.userName + ')'"
            :value="op.userId"
          />
        </el-select>
      </el-form-item>
      <el-form-item label="说明"><el-input v-model="handoverComment" class="w-220" /></el-form-item>
      <el-form-item><el-button type="primary" @click="doHandover">发起交接</el-button></el-form-item>
    </el-form>
    <el-table class="custom-table" :data="handovers">
      <template #empty><BrandedEmpty compact description="暂无交接" /></template>
      <el-table-column label="从" min-width="120">
        <template #default="scope">{{ scope.row.fromUserName || scope.row.fromUserId }}</template>
      </el-table-column>
      <el-table-column label="到" min-width="120">
        <template #default="scope">{{ scope.row.toUserName || scope.row.toUserId }}</template>
      </el-table-column>
      <el-table-column label="状态" width="100">
        <template #default="scope">{{ scope.row.status === 'confirmed' ? '已确认' : '待确认' }}</template>
      </el-table-column>
      <el-table-column label="时间" prop="createTime" />
      <el-table-column v-if="canEdit" label="操作" width="100">
        <template #default="scope">
          <el-button v-if="scope.row.status === 'pending' && String(scope.row.toUserId) === String(userStore.userId)" link type="primary" @click="doConfirm(scope.row)">确认</el-button>
        </template>
      </el-table-column>
    </el-table>
  </div>
</template>

<script setup>
import { dutySummary, listHandovers, listDutyOperators, createHandover, confirmHandover } from '@/api/wear/duty'
import { taskStatusLabel, ticketStatusLabel } from '@/api/wear/tasks'
import { eventTypeLabel, eventStatusLabel } from '@/api/wear/events'
import useUserStore from '@/store/modules/user'

const userStore = useUserStore()
const { proxy } = getCurrentInstance()
const canEdit = computed(() => userStore.canEditTask)
const hasSite = computed(() => !!userStore.currentSiteId)
const summary = ref({})
const handovers = ref([])
const handoverTo = ref('')
const handoverComment = ref('')
const operators = ref([])

function unwrap(res) {
  return res && res.data !== undefined ? res.data : res
}

function load() {
  if (!userStore.currentSiteId) {
    summary.value = {}
    handovers.value = []
    operators.value = []
    return
  }
  dutySummary().then(res => { summary.value = unwrap(res) || {} }).catch(() => { summary.value = {} })
  listHandovers().then(res => {
    const data = unwrap(res)
    handovers.value = Array.isArray(data) ? data : (data && data.records) || []
  }).catch(() => { handovers.value = [] })
  if (canEdit.value) {
    listDutyOperators().then(res => { operators.value = unwrap(res) || [] }).catch(() => { operators.value = [] })
  }
}

function goEvents(query) {
  proxy.$router.push({ path: '/business/events', query: query || {} })
}

function goMine() {
  goEvents({ claimantUserId: String(userStore.userId || '') })
}

function goLost() {
  proxy.$modal.msgWarning('失去监护：进行中任务里安全帽未有效。安全带无协议，不计入。已打开人员位置。')
  proxy.$router.push('/business/locations')
}

function openTask(row) {
  proxy.$router.push({ path: '/business/work-tasks', query: { id: row.id } })
}

function openEvent(row) {
  proxy.$router.push({ path: '/business/events', query: row && row.id ? { id: row.id } : {} })
}

function doHandover() {
  if (!handoverTo.value) {
    proxy.$modal.msgError('请选择接班人')
    return
  }
  createHandover({ toUserId: handoverTo.value, comment: handoverComment.value }).then(() => {
    proxy.$modal.msgSuccess('已发起，待接班人确认')
    handoverTo.value = ''
    handoverComment.value = ''
    load()
  })
}

function doConfirm(row) {
  confirmHandover(row.id).then(() => {
    proxy.$modal.msgSuccess('已确认交接')
    load()
  })
}

function onSiteChanged() { load() }

onMounted(() => {
  load()
  window.addEventListener('site-changed', onSiteChanged)
})
onUnmounted(() => window.removeEventListener('site-changed', onSiteChanged))
</script>

<style scoped>
.mb8 { margin-bottom: 12px; }
.stat-row { margin-bottom: 12px; }
.stat { padding: 12px; border: 1px solid var(--el-border-color-lighter); border-radius: 8px; cursor: pointer; margin-bottom: 8px; }
.stat b { display: block; font-size: 22px; }
.stat.warn b { color: var(--el-color-danger); }
.hint { color: var(--el-text-color-secondary); margin-bottom: 16px; }
.flow {
  margin: 0 0 16px;
  padding: 12px 12px 12px 32px;
  background: #f8fafc;
  border: 1px solid #e2e8f0;
  border-radius: 8px;
  color: #334155;
  font-size: 13px;
  line-height: 1.7;
}
.mt8 { margin-top: 8px; }
.w-180 { width: 180px; }
.w-220 { width: 220px; }
</style>
