<template>
  <div class="app-container events-workspace">
    <ModuleHeader
      module="system"
      title="安全事件"
      description="现场记录提交与管理员复核分开；平台核验不代表外部结案。"
    />
    <el-form class="search-form" :inline="true" :model="queryParams">
      <el-form-item label="类型">
        <el-select v-model="queryParams.type" class="w-140" clearable placeholder="全部">
          <el-option label="SOS" value="sos" />
          <el-option label="坠落" value="fall" />
          <el-option label="冲击" value="impact" />
          <el-option label="围栏" value="geofence" />
          <el-option label="实时告警" value="realtime" />
        </el-select>
      </el-form-item>
      <el-form-item label="状态">
        <el-select v-model="queryParams.status" class="w-140" clearable placeholder="核验待办">
          <el-option label="待认领" value="open" />
          <el-option label="已认领" value="claimed" />
          <el-option label="处置中" value="handling" />
          <el-option label="待复核" value="pending_review" />
          <el-option label="已核验" value="verified" />
          <el-option label="历史已处理" value="closed" />
        </el-select>
      </el-form-item>
      <el-form-item>
        <el-button type="primary" icon="Search" @click="handleQuery">搜索</el-button>
        <el-button icon="Refresh" @click="resetQuery">重置</el-button>
        <el-button v-if="canSimulate" @click="openSimulate">模拟事件</el-button>
      </el-form-item>
    </el-form>
    <div class="events-split">
      <div class="events-list">
        <div class="list-head">{{ listHead }} {{ total }}</div>
        <el-table v-loading="loading" class="custom-table" :data="list" highlight-current-row @row-click="selectRow">
          <template #empty><BrandedEmpty compact description="暂无事件" /></template>
          <el-table-column label="类型" width="88">
            <template #default="scope">{{ eventTypeLabel(scope.row.type) }}</template>
          </el-table-column>
          <el-table-column label="状态" width="90">
            <template #default="scope">{{ eventStatusLabel(scope.row.status) }}</template>
          </el-table-column>
          <el-table-column label="人员" min-width="100">
            <template #default="scope">{{ scope.row.personName || '未知' }}</template>
          </el-table-column>
          <el-table-column label="标记" width="72">
            <template #default="scope">
              <el-tag v-if="scope.row.demo" type="warning" size="small">演示</el-tag>
            </template>
          </el-table-column>
        </el-table>
        <pagination v-show="total > 0" v-model:page="queryParams.current" v-model:limit="queryParams.size" :total="total" @pagination="getList" />
      </div>
      <div class="events-detail">
        <template v-if="detail.id">
          <div class="detail-title">
            {{ eventTypeLabel(detail.type) }}
            <el-tag v-if="detail.demo" type="warning" size="small" class="ml8">演示</el-tag>
            <el-tag v-if="detail.escalated" type="danger" size="small" class="ml8">已升级</el-tag>
          </div>
          <p class="detail-line">状态：{{ eventStatusLabel(detail.status) }}（{{ statusHint(detail.status) }}）</p>
          <p class="detail-line">人员快照：{{ detail.personName || '未知' }} {{ detail.personCode || '' }}</p>
          <p class="detail-line">设备快照：{{ detail.sn || '未知' }}</p>
          <p class="detail-line">发生时间：{{ detail.occurredAt || '-' }}</p>
          <p class="detail-line">位置：{{ locationText(detail) }}</p>
          <p class="detail-line">重复次数：{{ detail.repeatCount || 0 }}　来源：{{ sourceLabel(detail) }}</p>
          <p class="detail-line">作业任务：{{ taskMatchLabel(detail.taskMatch) }}{{ detail.taskId ? ' #' + detail.taskId : '' }}</p>
          <p v-if="detail.fenceId" class="detail-line">围栏：#{{ detail.fenceId }} {{ fenceActionLabel(detail.fenceAction) }}　规则 {{ detail.ruleVersion || '-' }}</p>
          <div v-if="canClaim && detail.taskMatch === 'pending'" class="detail-actions">
            <el-select v-model="confirmTaskId" class="w-140" placeholder="选择任务" clearable>
              <el-option v-for="item in taskOptions" :key="item.id" :label="item.title" :value="item.id" />
            </el-select>
            <el-button @click="doAssignTask">确认关联</el-button>
          </div>
          <div class="detail-actions">
            <el-button v-if="canClaim && detail.status === 'open'" type="primary" @click="doClaim">认领</el-button>
            <el-button v-if="canClaim && (detail.status === 'claimed' || detail.status === 'handling')" @click="openHandle">处置</el-button>
            <el-button v-if="canClaim && (detail.status === 'claimed' || detail.status === 'handling')" @click="openTransfer">转交</el-button>
            <el-button v-if="canCloseHigh" type="success" @click="openClose">审批通过 · 完成核验</el-button>
            <el-button v-if="canReview && ['closed', 'verified'].includes(detail.status)" @click="openReopen">重开</el-button>
            <el-button v-if="canClaim || canReview" @click="doAck">已看见</el-button>
            <el-button v-if="canCallDevice" type="warning" @click="doCall">联系</el-button>
            <el-button v-if="canTtsDevice" @click="openTts">播报</el-button>
          </div>
          <p v-if="callSession.id" class="detail-line">
            通话：{{ callStatusLabel(callSession.status) }}
            <el-tag v-if="callSession.demo" type="warning" size="small" class="ml8">演示通道</el-tag>
            <el-tag v-if="isCallConnected(callSession.status)" type="success" size="small" class="ml8">已接通</el-tag>
          </p>
          <div v-if="callSession.id && canStartCall" class="detail-actions">
            <el-button v-if="callSession.status === 'offered'" type="primary" @click="doJoin">确认加入</el-button>
            <el-button v-if="callSession.status === 'offered' || callSession.status === 'connected'" @click="doHangup">结束</el-button>
          </div>
          <p class="detail-line">外部结案：未同步。正式结案由原安监系统确认。</p>
          <div class="timeline-title">动作时间线</div>
          <el-timeline>
            <el-timeline-item v-for="item in actions" :key="item.id" :timestamp="item.createTime">
              {{ actionLabel(item.action) }}　{{ item.actor }}　{{ item.reason || '' }}
              <span v-if="item.fromStatus || item.toStatus">（{{ eventStatusLabel(item.fromStatus) }} → {{ eventStatusLabel(item.toStatus) }}）</span>
            </el-timeline-item>
          </el-timeline>
          <p v-if="!actions.length" class="detail-line">暂无动作。已看见 / 已认领 / 历史已处理会分别出现在这里。</p>
        </template>
        <BrandedEmpty v-else compact description="从左侧选择事件" />
      </div>
    </div>

    <el-dialog v-model="handleOpen" title="处置" width="420px">
      <el-form label-width="80px">
        <el-form-item label="说明"><el-input v-model="handleComment" type="textarea" rows="3" /></el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="handleOpen = false">取消</el-button>
        <el-button type="primary" @click="doHandle">提交</el-button>
      </template>
    </el-dialog>
    <el-dialog v-model="closeOpen" title="审批现场核验" width="420px">
      <el-form label-width="80px">
        <el-form-item label="原因"><el-input v-model="closeReason" type="textarea" rows="3" placeholder="必填。误报请写明原因" /></el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="closeOpen = false">取消</el-button>
        <el-button type="primary" @click="doClose">审批通过</el-button>
      </template>
    </el-dialog>
    <el-dialog v-model="transferOpen" title="转交" width="420px">
      <el-form label-width="90px">
        <el-form-item label="转交给">
          <el-select v-model="transferUserId" filterable class="w-220" placeholder="选择值班/班组长">
            <el-option
              v-for="op in operators"
              :key="op.userId"
              :label="(op.nickName || op.userName) + ' (' + op.userName + ')'"
              :value="op.userId"
            />
          </el-select>
        </el-form-item>
        <el-form-item label="原因"><el-input v-model="transferReason" /></el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="transferOpen = false">取消</el-button>
        <el-button type="primary" @click="doTransfer">转交</el-button>
      </template>
    </el-dialog>
    <el-dialog v-model="reopenOpen" title="重开" width="420px">
      <el-form label-width="80px">
        <el-form-item label="原因"><el-input v-model="reopenReason" /></el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="reopenOpen = false">取消</el-button>
        <el-button type="primary" @click="doReopen">重开</el-button>
      </template>
    </el-dialog>
    <el-dialog v-model="simulateOpen" title="模拟事件" width="460px">
      <el-form label-width="100px">
        <el-form-item label="类型">
          <el-select v-model="simulateForm.type">
            <el-option label="SOS" value="sos" />
            <el-option label="围栏" value="geofence" />
            <el-option label="坠落" value="fall" />
          </el-select>
        </el-form-item>
        <el-form-item label="来源编号"><el-input v-model="simulateForm.sourceEventId" /></el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="simulateOpen = false">取消</el-button>
        <el-button type="primary" @click="doSimulate">生成</el-button>
      </template>
    </el-dialog>
    <el-dialog v-model="ttsOpen" title="播报" width="420px">
      <el-form label-width="80px">
        <el-form-item label="内容"><el-input v-model="ttsText" type="textarea" rows="3" /></el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="ttsOpen = false">取消</el-button>
        <el-button type="primary" @click="doTts">发送</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup>
import {
  listEvents, getEvent, listEventActions, inboxCount, ackEvent, claimEvent, handleEvent,
  transferEvent, closeEvent, reopenEvent, simulateEvent, eventTypeLabel, eventStatusLabel, fenceActionLabel
} from '@/api/wear/events'
import { startCall, joinCall, endCall, listEventCalls, sendTts, callStatusLabel, isCallConnected } from '@/api/wear/calls'
import { assignEventTask, listWorkTasks } from '@/api/wear/tasks'
import { listDutyOperators } from '@/api/wear/duty'
import { getDevice, supportsCapability } from '@/api/wear/devices'
import useUserStore from '@/store/modules/user'
import { canReviewVerification } from '@/api/wear/eventWorkflow'

const userStore = useUserStore()
const { proxy } = getCurrentInstance()
const canClaim = computed(() => userStore.canClaimEvent)
const canReview = computed(() => userStore.isPlatformAdmin && userStore.canReviewEvent)
const canSimulate = computed(() => import.meta.env.MODE !== 'production' && (canClaim.value || userStore.isPlatformAdmin))
const canCloseHigh = computed(() => canReviewVerification(detail.value, userStore, actions.value))
const canStartCall = computed(() => userStore.canStartCall)
const canSendTts = computed(() => userStore.canSendTts)
const eventDevice = ref({})
const canCallDevice = computed(() => canStartCall.value && detail.value.deviceId && supportsCapability(eventDevice.value, 'intercom'))
const canTtsDevice = computed(() => canSendTts.value && detail.value.deviceId && supportsCapability(eventDevice.value, 'tts'))

const loading = ref(false)
const list = ref([])
const total = ref(0)
const openCount = ref(0)
const queryParams = reactive({ current: 1, size: 10, type: '', status: '', claimantUserId: '', escalated: '' })
const detail = ref({})
const actions = ref([])
const handleOpen = ref(false)
const handleComment = ref('')
const closeOpen = ref(false)
const closeReason = ref('')
const transferOpen = ref(false)
const transferUserId = ref('')
const transferReason = ref('')
const reopenOpen = ref(false)
const reopenReason = ref('')
const simulateOpen = ref(false)
const simulateForm = reactive({ type: 'sos', sourceEventId: '' })
const callSession = ref({})
const ttsOpen = ref(false)
const ttsText = ref('')
const confirmTaskId = ref('')
const taskOptions = ref([])
const operators = ref([])
const route = useRoute()
const listHead = computed(() => {
  if (queryParams.status === 'verified') return '已核验'
  if (queryParams.status === 'closed') return '历史已处理'
  if (queryParams.escalated === 'true') return '已升级'
  if (queryParams.claimantUserId) return '我的处置'
  if (queryParams.status === 'open') return '待认领'
  return '核验待办'
})

function unwrap(res) {
  return res && res.data !== undefined ? res.data : res
}

function statusHint(status) {
  if (status === 'closed') return '历史已处理'
  return eventStatusLabel(status)
}

function locationText(row) {
  const quality = row.locationQuality === 'ok' ? '有效' : row.locationQuality === 'stale' ? '陈旧' : '未知'
  if (row.locationLat == null || row.locationLng == null) return '无坐标（' + quality + '）'
  return row.locationLat + ', ' + row.locationLng + '（' + quality + '）'
}

function taskMatchLabel(match) {
  if (match === 'matched') return '已关联'
  if (match === 'pending') return '待确认（多任务命中）'
  return '未关联'
}

function sourceLabel(row) {
  if (!row) return '-'
  if (row.source === 'helmet') return '设备上报'
  if (row.source === 'simulator') return '模拟器'
  if (row.source === 'geofence') return '围栏规则'
  return row.source || '-'
}

function actionLabel(action) {
  const map = { ack: '已看见', claim: '已认领', handle: '处置', transfer: '转交', close: '历史已处理', reopen: '重开', escalate: '升级', review: '复核' }
  return map[action] || action
}

function getList() {
  loading.value = true
  listEvents(queryParams).then(res => {
    const page = unwrap(res) || {}
    list.value = page.records || []
    total.value = page.total || 0
  }).finally(() => { loading.value = false })
  inboxCount().then(res => {
    const data = unwrap(res) || {}
    openCount.value = data.count || 0
  }).catch(() => { openCount.value = 0 })
}

function loadDetail(id) {
  if (!id) return
  confirmTaskId.value = ''
  listWorkTasks({ current: 1, size: 20, status: 'in_progress' }).then(res => {
    const page = unwrap(res) || {}
    taskOptions.value = page.records || []
  }).catch(() => { taskOptions.value = [] })
  getEvent(id).then(res => {
    detail.value = unwrap(res) || {}
    eventDevice.value = {}
    if (detail.value.deviceId) {
      getDevice(detail.value.deviceId).then(dev => { eventDevice.value = unwrap(dev) || {} }).catch(() => { eventDevice.value = {} })
    }
  })
  listEventActions(id).then(res => {
    actions.value = unwrap(res) || []
  }).catch(() => { actions.value = [] })
  listEventCalls(id).then(res => {
    const rows = unwrap(res) || []
    callSession.value = rows[0] || {}
  }).catch(() => { callSession.value = {} })
}

function selectRow(row) {
  loadDetail(row.id)
}

function handleQuery() {
  queryParams.current = 1
  getList()
}

function resetQuery() {
  queryParams.type = ''
  queryParams.status = ''
  queryParams.claimantUserId = ''
  queryParams.escalated = ''
  queryParams.current = 1
  getList()
}

function applyRouteQuery() {
  const q = route.query || {}
  queryParams.status = q.status ? String(q.status) : ''
  queryParams.claimantUserId = q.claimantUserId ? String(q.claimantUserId) : ''
  queryParams.escalated = q.escalated ? String(q.escalated) : ''
  queryParams.current = 1
  getList()
  if (q.id) {
    loadDetail(String(q.id))
  }
}

function refreshSelected() {
  getList()
  if (detail.value.id) loadDetail(detail.value.id)
}

function doAssignTask() {
  assignEventTask(detail.value.id, { taskId: confirmTaskId.value || null, version: detail.value.version }).then(() => {
    proxy.$modal.msgSuccess('已更新任务关联')
    refreshSelected()
  })
}

function doAck() {
  ackEvent(detail.value.id).then(() => {
    proxy.$modal.msgSuccess('已看见')
    refreshSelected()
  })
}

function doClaim() {
  claimEvent(detail.value.id, { version: detail.value.version }).then(() => {
    proxy.$modal.msgSuccess('已认领')
    refreshSelected()
  })
}

function openHandle() {
  handleComment.value = ''
  handleOpen.value = true
}

function doHandle() {
  handleEvent(detail.value.id, { comment: handleComment.value, version: detail.value.version }).then(() => {
    handleOpen.value = false
    proxy.$modal.msgSuccess('已提交处置')
    refreshSelected()
  })
}

function openClose() {
  closeReason.value = ''
  closeOpen.value = true
}

function doClose() {
  closeEvent(detail.value.id, { reason: closeReason.value, version: detail.value.version }).then(() => {
    closeOpen.value = false
    proxy.$modal.msgSuccess('平台核验已完成，外部结案未同步')
    refreshSelected()
  })
}

function openTransfer() {
  transferUserId.value = ''
  transferReason.value = ''
  listDutyOperators().then(res => { operators.value = unwrap(res) || [] }).catch(() => { operators.value = [] })
  transferOpen.value = true
}

function doTransfer() {
  transferEvent(detail.value.id, { toUserId: transferUserId.value, reason: transferReason.value, version: detail.value.version }).then(() => {
    transferOpen.value = false
    proxy.$modal.msgSuccess('已转交')
    refreshSelected()
  })
}

function openReopen() {
  reopenReason.value = ''
  reopenOpen.value = true
}

function doReopen() {
  reopenEvent(detail.value.id, { reason: reopenReason.value, version: detail.value.version }).then(() => {
    reopenOpen.value = false
    proxy.$modal.msgSuccess('已重开')
    refreshSelected()
  })
}

function openSimulate() {
  simulateForm.type = 'sos'
  simulateForm.sourceEventId = 'sim-' + Date.now()
  simulateOpen.value = true
}

function doCall() {
  startCall({
    deviceId: detail.value.deviceId,
    eventId: detail.value.id,
    kind: detail.value.type === 'sos' ? 'sos' : 'single',
    video: supportsCapability(eventDevice.value, 'video')
  }).then(res => {
    callSession.value = unwrap(res) || {}
    proxy.$modal.msgSuccess(callSession.value.demo ? '演示通道已就绪，确认加入后才算接通' : '待加入')
  })
}

function doJoin() {
  joinCall(callSession.value.id, { agoraUid: callSession.value.credentials && callSession.value.credentials.agoraUid }).then(res => {
    callSession.value = unwrap(res) || callSession.value
    proxy.$modal.msgSuccess('已接通')
  })
}

function doHangup() {
  endCall(callSession.value.id).then(res => {
    callSession.value = unwrap(res) || {}
    proxy.$modal.msgSuccess('已结束')
  })
}

function openTts() {
  ttsText.value = ''
  ttsOpen.value = true
}

function doTts() {
  sendTts({ deviceIds: [detail.value.deviceId], text: ttsText.value, eventId: detail.value.id }).then(res => {
    ttsOpen.value = false
    const rows = unwrap(res) || []
    const first = rows[0] || {}
    proxy.$modal.msgSuccess(first.status === 'accepted' ? '平台已受理（未确认现场听到）' : '已下发（未确认现场听到）')
  })
}

function doSimulate() {
  const payload = {
    sourceEventId: simulateForm.sourceEventId,
    type: simulateForm.type,
    siteId: userStore.currentSiteId
  }
  simulateEvent(payload).then(res => {
    simulateOpen.value = false
    proxy.$modal.msgSuccess('已生成演示事件')
    const created = unwrap(res) || {}
    getList()
    if (created.id) loadDetail(created.id)
  })
}

function onSiteChanged() {
  detail.value = {}
  actions.value = []
  getList()
}

function onWearEvent() {
  getList()
  if (detail.value.id) loadDetail(detail.value.id)
}

onMounted(() => {
  applyRouteQuery()
  window.addEventListener('site-changed', onSiteChanged)
  window.addEventListener('wear-event', onWearEvent)
  window.addEventListener('wear-event-connected', onWearEvent)
})
watch(() => route.query, () => applyRouteQuery())
onUnmounted(() => {
  window.removeEventListener('site-changed', onSiteChanged)
  window.removeEventListener('wear-event', onWearEvent)
  window.removeEventListener('wear-event-connected', onWearEvent)
})
</script>

<style scoped>
.events-split { display: flex; gap: 16px; align-items: stretch; min-height: 480px; }
.events-list { width: 420px; flex-shrink: 0; }
.events-detail { flex: 1; min-width: 0; padding: 12px 16px; background: var(--el-fill-color-blank, #fff); border: 1px solid var(--el-border-color-lighter); border-radius: 8px; }
.list-head { margin-bottom: 8px; font-weight: 600; }
.detail-title { font-size: 18px; font-weight: 600; margin-bottom: 12px; }
.detail-line { margin: 6px 0; color: var(--el-text-color-regular); }
.detail-actions { margin: 16px 0; display: flex; flex-wrap: wrap; gap: 8px; }
.timeline-title { margin: 16px 0 8px; font-weight: 600; }
.ml8 { margin-left: 8px; }
.w-140 { width: 140px; }
.w-220 { width: 220px; }
</style>
