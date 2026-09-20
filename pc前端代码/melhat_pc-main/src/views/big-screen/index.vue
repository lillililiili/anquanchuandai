<template>
  <div ref="screenRoot" class="big-screen">
    <!-- 头部标题栏 -->
    <header class="screen-header">
      <router-link class="screen-back" to="/">‹ 返回工作台</router-link>
      <div class="header-center">
        <div class="header-content">
          <div class="header-logo-centered">
            <BrandLogo compact />
          </div>
          <h1 class="header-title">分体式智能安全帽平台</h1>
        </div>
      </div>
      <div class="header-right">
        <span class="header-time">{{ currentDateTime }}</span>
      </div>
    </header>

    <!-- 主体内容区 -->
    <main class="screen-main">
      <!-- 左侧区域 -->
      <section class="screen-left">
        <!-- 左侧上部：概览数据 -->
        <div class="screen-card overview-card">
          <div class="card-header">
            <div class="card-title">
              <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor"><path d="M16 11c1.66 0 2.99-1.34 2.99-3S17.66 5 16 5c-1.66 0-3 1.34-3 3s1.34 3 3 3zm-8 0c1.66 0 2.99-1.34 2.99-3S9.66 5 8 5C6.34 5 5 6.34 5 8s1.34 3 3 3zm0 2c-2.33 0-7 1.17-7 3.5V19h14v-2.5c0-2.33-4.67-3.5-7-3.5zm8 0c-.29 0-.62.02-.97.05 1.16.84 1.97 1.97 1.97 3.45V19h6v-2.5c0-2.33-4.67-3.5-7-3.5z"/></svg>
              实时概览
            </div>
          </div>
          <div class="card-body">
            <div class="overview-stats">
              <div class="overview-stat-item">
                <span class="stat-num">1</span>
                <span class="stat-label">在线人员</span>
              </div>
              <div class="overview-stat-divider"></div>
              <div class="overview-stat-item">
                <span class="stat-num">8</span>
                <span class="stat-label">今日告警</span>
              </div>
              <div class="overview-stat-divider"></div>
              <div class="overview-stat-item">
                <span class="stat-num">99%</span>
                <span class="stat-label">设备正常率</span>
              </div>
            </div>
          </div>
        </div>

        <!-- 左侧中部：实时告警 -->
        <div class="screen-card">
          <div class="card-header">
            <div class="card-title">
              <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor"><path d="M1 21h22L12 2 1 21zm12-3h-2v-2h2v2zm0-4h-2v-4h2v4z"/></svg>
              实时告警
            </div>
            <button class="card-extra" type="button" @click="goToSos">查看全部</button>
          </div>
          <div class="card-body">
            <div v-loading="panelLoading.alarms" class="alarm-list">
              <div v-if="!panelLoading.alarms && alarmList.length === 0" class="panel-empty">{{ panelErrors.alarms ? '数据暂不可用' : '暂无待处理告警' }}</div>
              <div v-for="(item, index) in alarmList" :key="index" class="alarm-item" :class="`alarm-level-${item.level}`">
                <div class="alarm-icon">
                  <svg viewBox="0 0 24 24" width="20" height="20" fill="currentColor"><path d="M12 22c1.1 0 2-.9 2-2h-4c0 1.1.9 2 2 2zm6-6v-5c0-3.07-1.64-5.64-4.5-6.32V4c0-.83-.67-1.5-1.5-1.5s-1.5.67-1.5 1.5v.68C7.63 5.36 6 7.92 6 11v5l-2 2v1h16v-1l-2-2z"/></svg>
                </div>
                <div class="alarm-info">
                  <div class="alarm-title">{{ item.title }}</div>
                  <div class="alarm-desc">{{ item.desc }}</div>
                </div>
                <div class="alarm-time">{{ item.time }}</div>
              </div>
            </div>
          </div>
        </div>

        <!-- 左侧下部：组呼对讲 -->
        <div class="screen-card communication-card">
          <div class="card-header">
            <div class="card-title">
              <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor"><path d="M16 11c1.66 0 2.99-1.34 2.99-3S17.66 5 16 5c-1.66 0-3 1.34-3 3s1.34 3 3 3zm-8 0c1.66 0 2.99-1.34 2.99-3S9.66 5 8 5C6.34 5 5 6.34 5 8s1.34 3 3 3zm0 2c-2.33 0-7 1.17-7 3.5V19h14v-2.5c0-2.33-4.67-3.5-7-3.5zm8 0c-.29 0-.62.02-.97.05 1.16.84 1.97 1.97 1.97 3.45V19h6v-2.5c0-2.33-4.67-3.5-7-3.5z"/></svg>
              组呼对讲
            </div>
            <button class="card-extra" type="button" @click="goToIntercom">查看全部</button>
          </div>
          <div class="card-body">
            <div v-loading="panelLoading.groups" class="group-list">
              <div v-if="!panelLoading.groups && groupList.length === 0" class="panel-empty">{{ panelErrors.groups ? '数据暂不可用' : '暂无作业群组' }}</div>
              <div v-for="(item, index) in groupList" :key="index" class="group-item">
                <div class="group-avatar">
                  <svg viewBox="0 0 24 24" width="20" height="20" fill="currentColor"><path d="M16 11c1.66 0 2.99-1.34 2.99-3S17.66 5 16 5c-1.66 0-3 1.34-3 3s1.34 3 3 3zm-8 0c1.66 0 2.99-1.34 2.99-3S9.66 5 8 5C6.34 5 5 6.34 5 8s1.34 3 3 3zm0 2c-2.33 0-7 1.17-7 3.5V19h14v-2.5c0-2.33-4.67-3.5-7-3.5zm8 0c-.29 0-.62.02-.97.05 1.16.84 1.97 1.97 1.97 3.45V19h6v-2.5c0-2.33-4.67-3.5-7-3.5z"/></svg>
                </div>
                <div class="group-info">
                  <div class="group-name" :title="item.name">{{ item.name }}</div>
                </div>
                <button class="group-btn" :class="{ 'single-btn-calling': callStatusMap[item.deviceNos || item.id] }" :disabled="!!callStatusMap[item.deviceNos || item.id]" @click="handleTeamCall(item)">{{ callStatusMap[item.deviceNos || item.id] || '呼叫' }}</button>
              </div>
            </div>
          </div>
        </div>
      </section>

      <!-- 中间核心区域 -->
      <section class="screen-center">
        <!-- 中间上部：工作人员实时位置 -->
        <div class="screen-card center-top">
          <div class="card-header">
            <div class="card-title">
              <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor"><path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z"/></svg>
              工作人员实时位置
            </div>
          </div>
          <div class="card-body">
            <div ref="mapContainer" class="map-view"></div>
          </div>
        </div>

        <!-- 中间下部：最近一周数据统计 -->
        <div class="screen-card center-bottom">
          <div class="card-header">
            <div class="card-title">
              <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor"><path d="M19 3H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zM9 17H7v-7h2v7zm4 0h-2V7h2v10zm4 0h-2v-4h2v4z"/></svg>
              最近一周数据统计
            </div>
          </div>
          <div class="card-body stats-charts">
            <section v-loading="chartLoading.alarm" class="chart-panel" aria-label="告警趋势">
              <h2>告警趋势</h2>
              <div ref="alarmStatsRef" class="stats-chart"></div>
              <p v-if="chartErrors.alarm" class="panel-empty chart-error">统计暂不可用</p>
            </section>
            <section v-loading="chartLoading.intercom" class="chart-panel" aria-label="对讲统计">
              <h2>对讲统计</h2>
              <div ref="intercomStatsRef" class="stats-chart"></div>
              <p v-if="chartErrors.intercom" class="panel-empty chart-error">统计暂不可用</p>
            </section>
            <section v-loading="chartLoading.tts" class="chart-panel" aria-label="广播统计">
              <h2>广播统计</h2>
              <div ref="ttsStatsRef" class="stats-chart"></div>
              <p v-if="chartErrors.tts" class="panel-empty chart-error">统计暂不可用</p>
            </section>
          </div>
        </div>
      </section>

      <!-- 右侧区域 -->
      <section class="screen-right">
        <!-- 右侧上部：单呼对讲 -->
        <div class="screen-card communication-card">
          <div class="card-header">
            <div class="card-title">
              <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor"><path d="M6.62 10.79c1.44 2.83 3.76 5.14 6.59 6.59l2.2-2.2c.27-.27.67-.36 1.02-.24 1.12.37 2.33.57 3.57.57.55 0 1 .45 1 1V20c0 .55-.45 1-1 1-9.39 0-17-7.61-17-17 0-.55.45-1 1-1h3.5c.55 0 1 .45 1 1 0 1.25.2 2.45.57 3.57.11.35.03.74-.25 1.02l-2.2 2.2z"/></svg>
              单呼对讲
            </div>
            <button class="card-extra" type="button" @click="goToIntercom">查看全部</button>
          </div>
          <div class="card-body">
            <div v-loading="panelLoading.people" class="single-list">
              <div v-if="!panelLoading.people && singleList.length === 0" class="panel-empty">{{ panelErrors.people ? '数据暂不可用' : '暂无可用设备' }}</div>
              <div v-for="(item, index) in singleList" :key="index" class="single-item">
                <div class="single-avatar">
                  <svg viewBox="0 0 24 24" width="24" height="24" fill="currentColor"><path d="M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z"/></svg>
                </div>
                <div class="single-info">
                  <div class="single-name" :class="`status-${item.status === '在线' ? 'online' : 'offline'}`"><span class="person-label" :title="item.userName || item.deviceNo">{{ item.userName || item.deviceNo || '未绑定设备' }}</span></div>
                  <div class="single-group" :title="`${item.group || '未分组'} | ${callStatusMap[item.deviceNo] || item.status}`">{{ item.group || '未分组' }} | <span :class="callStatusMap[item.deviceNo] ? 'calling-text' : ''">{{ callStatusMap[item.deviceNo] || item.status }}</span></div>
                </div>
                <button class="single-btn" :class="{ 'single-btn-calling': callStatusMap[item.deviceNo] }" :disabled="!!callStatusMap[item.deviceNo]" @click="handleSingleCall(item)">{{ callStatusMap[item.deviceNo] || '呼叫' }}</button>
              </div>
            </div>
          </div>
        </div>

        <!-- 右侧下部：群呼对讲 -->
        <div class="screen-card communication-card">
          <div class="card-header">
            <div class="card-title">
              <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 16c-3.31 0-6-2.69-6-6s2.69-6 6-6 6 2.69 6 6-2.69 6-6 6zm-1-8h2v6h-2zm0-4h2v2h-2z"/></svg>
              群呼对讲
            </div>
            <div class="card-extra-group">
              <button class="header-call-btn" :disabled="selectedDeviceNos.length < 2" @click="handleBroadcastCall">呼叫</button>
              <button class="card-extra" type="button" @click="goToIntercom">查看全部</button>
            </div>
          </div>
          <div class="card-body">
            <div v-loading="panelLoading.people" class="broadcast-list">
              <div v-if="!panelLoading.people && broadcastList.length === 0" class="panel-empty">{{ panelErrors.people ? '数据暂不可用' : '暂无可用设备' }}</div>
              <div v-for="(item, index) in broadcastList" :key="index" class="broadcast-item" :class="{ 'is-selected': selectedDeviceNos.includes(item.deviceNo) }">
                <div class="single-avatar">
                  <svg viewBox="0 0 24 24" width="24" height="24" fill="currentColor"><path d="M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z"/></svg>
                </div>
                <div class="single-info">
                  <div class="single-name" :class="`status-${item.status === '在线' ? 'online' : 'offline'}`"><span class="person-label" :title="item.userName || item.deviceNo">{{ item.userName || item.deviceNo || '未绑定设备' }}</span></div>
                  <div class="single-group" :title="`${item.group || '未分组'} | ${callStatusMap[item.deviceNo] || item.status}`">{{ item.group || '未分组' }} | <span :class="callStatusMap[item.deviceNo] ? 'calling-text' : ''">{{ callStatusMap[item.deviceNo] || item.status }}</span></div>
                </div>
                <button
                  class="broadcast-btn"
                  :class="{ 'broadcast-btn-selected': selectedDeviceNos.includes(item.deviceNo) }"
                  @click="handleBroadcastSelect(item)"
                >
                  {{ selectedDeviceNos.includes(item.deviceNo) ? '已选择' : '选择' }}
                </button>
              </div>
            </div>
          </div>
        </div>
      </section>
    </main>

    <!-- 视频对讲弹窗 -->
    <AgoraVideoDialog
      v-model="openVideo"
      :title="videoTitle"
      :credentials="agoraCredentials"
      :device-no="videoDeviceNo"
      :user-name="videoUserName"
      :is-playback="videoTitle === '回放'"
      @hangup="handleHangup"
      @replay="handleReplay"
      @credentials-clear="handleCredentialsClear"
    />
  </div>
</template>

<script setup>
import { ref, onMounted, onBeforeUnmount, nextTick, getCurrentInstance } from 'vue'
import { useRouter } from 'vue-router'
import { useECharts } from '@/hooks/useECharts'
import { useMap } from '@/hooks/useMap'
import 'ol/ol.css'
import { hatSafetyInfoPage, hatSafetyInfoList } from '@/api/helmet'
import { groupList as fetchGroupList } from '@/api/group'
import { createSingleCall, createGroupCall, createTeamCall, endIntercom, getIntercomRecord, listIntercomRecord } from '@/api/intercom'
import { listAlarmPage } from '@/api/system/sos'
import { listTtsRecord } from '@/api/tts'
import AgoraVideoDialog from '@/components/AgoraVideoDialog/index.vue'

const { proxy } = getCurrentInstance()
const router = useRouter()
const screenRoot = ref(null)
const panelLoading = ref({ alarms: true, groups: true, people: true })
const panelErrors = ref({ alarms: false, groups: false, people: false })
const chartLoading = ref({ alarm: true, intercom: true, tts: true })
const chartErrors = ref({ alarm: false, intercom: false, tts: false })
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches
let layoutObserver = null
let layoutFrame = null
let mapTimer = null
let markerTimer = null
function resizePanels() {
  cancelAnimationFrame(layoutFrame)
  layoutFrame = requestAnimationFrame(() => {
    resizeAlarmStats(); resizeIntercomStats(); resizeTtsStats()
    mapUtils?.map?.value?.updateSize()
  })
}
const { alarm_type } = proxy.useDict('alarm_type')

// ===== 声网视频弹窗相关 =====
const openVideo = ref(false)
const videoTitle = ref('呼叫详情')
const videoDeviceNo = ref('')
const videoUserName = ref('')
const agoraCredentials = ref(null)
const currentRecordId = ref(null)

// ===== 呼叫状态追踪 =====
const callStatusMap = ref({})

function extractAgoraCredentials(res) {
  const { agoraAppId, channelName, agoraUid, agoraToken } = res
  return { agoraAppId, channelName, agoraUid, agoraToken }
}

function handleHangup() {
  if (videoTitle.value !== '回放' && agoraCredentials.value?.channelName) {
    endIntercom({ channel: agoraCredentials.value.channelName }).then(() => {
      Object.keys(callStatusMap.value).forEach(key => {
        callStatusMap.value[key] = ''
      })
    })
  }
  agoraCredentials.value = null
  openVideo.value = false
}

function handleCredentialsClear() {
  if (agoraCredentials.value?.channelName) {
    endIntercom({ channel: agoraCredentials.value.channelName }).then(() => {
      Object.keys(callStatusMap.value).forEach(key => {
        callStatusMap.value[key] = ''
      })
    })
  }
  agoraCredentials.value = null
}

function handleReplay() {
  if (currentRecordId.value) {
    getIntercomRecord(currentRecordId.value).then(res => {
      if (res.code === 200) {
        const credentials = extractAgoraCredentials(res.data)
        if (credentials?.agoraAppId) {
          agoraCredentials.value = credentials
        }
      }
    })
  }
}

// ===== 时间显示 =====
const currentDateTime = ref('')
let timer = null

function updateTime() {
  const now = new Date()
  currentDateTime.value = `${now.getFullYear()}年${now.getMonth() + 1}月${now.getDate()}日 ${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}:${String(now.getSeconds()).padStart(2, '0')}`
}

// ===== 实时告警列表 =====
const alarmList = ref([])

function getAlarmLevel(level) {
  switch (Number(level)) {
    case 1: return 'high'
    case 2: return 'medium'
    case 3: return 'low'
    case 4: return 'low'
    default: return 'neutral'
  }
}

function getAlarmTypeLabel(type) {
  const item = alarm_type.value?.find(d => d.value === type)
  return item ? item.label : type || '告警'
}

function loadAlarmList() {
  listAlarmPage({ current: 1, size: 8, isHandled: 0 }).then(res => {
    if (res.code === 200) {
      alarmList.value = (res.data?.records || []).map(item => ({
        title: getAlarmTypeLabel(item.alarmType),
        desc: item.description || `${item.userName || ''} | ${item.hatNumber || ''}`,
        time: item.alarmStartTime ? item.alarmStartTime.slice(11, 16) : '',
        level: getAlarmLevel(item.alarmLevel)
      }))
    }
  }).catch(() => { panelErrors.value.alarms = true }).finally(() => { panelLoading.value.alarms = false })
}

// ===== 组呼对讲列表 =====
const groupList = ref([])
const helmetAllList = ref([])

// ===== 单呼对讲列表 =====
const singleList = ref([])

// ===== 群呼对讲列表 =====
const broadcastList = ref([])
const selectedDeviceNos = ref([])

// 加载安全帽列表（单呼 + 群呼共用）
function loadHelmetList() {
  return hatSafetyInfoPage({ current: 1, size: 8 }).then(res => {
    if (res.code === 200) {
      const records = res.data?.records || []
      const list = records.map(item => ({
        ...item,
        deviceNo: item.hatNumber || item.deviceNo,
        userName: item.userName || item.bindUserName,
        group: item.bindGroup || item.groupName || item.group,
        status: item.status == 1 ? '在线' : item.status == 0 ? '离线' : '未知'
      }))
      singleList.value = list
      broadcastList.value = list
    }
  }).catch(() => { panelErrors.value.people = true }).finally(() => { panelLoading.value.people = false })
}

// 加载全部安全帽（用于组呼统计）
function loadHelmetAllList() {
  return hatSafetyInfoList().then(res => {
    if (res.code === 200) {
      helmetAllList.value = res.data || []
    }
  })
}

// 加载组呼分组列表
function loadGroupList() {
  return fetchGroupList({ current: 1, size: 8 }).then(res => {
    if (res.code === 200) {
      const records = res.data?.records || res.data || []
      groupList.value = records.map(item => {
        const groupName = item.groupName || item.name || ''
        // 统计该分组的在线/离线数量
        const groupHelmets = helmetAllList.value.filter(h =>
          (h.bindGroup || h.groupName || '') === groupName
        )
        const online = groupHelmets.filter(h => h.status == 1).length
        const offline = groupHelmets.filter(h => h.status == 0).length
        return {
          ...item,
          name: groupName,
          online,
          offline,
          color: item.color || getGroupColor(item.id)
        }
      })
    }
  }).catch(() => { panelErrors.value.groups = true }).finally(() => { panelLoading.value.groups = false })
}

function getGroupColor(id) {
  return chartPalette[(id || 0) % chartPalette.length]
}

// 单呼呼叫
function handleSingleCall(row) {
  callStatusMap.value[row.deviceNo] = '呼叫中'
  createSingleCall({ hatNumber: row.deviceNo, participant: row.userName }).then(res => {
    if (res.code === 200) {
      currentRecordId.value = res.data?.id
      videoTitle.value = '呼叫详情'
      videoDeviceNo.value = row.deviceNo
      videoUserName.value = row.userName
      const credentials = extractAgoraCredentials(res.data)
      if (credentials?.agoraAppId) {
        agoraCredentials.value = credentials
        openVideo.value = true
      } else {
        proxy.$modal.msgWarning('未获取到音视频凭证，仅创建了对讲记录')
      }
      callStatusMap.value[row.deviceNo] = '对讲中'
    } else {
      callStatusMap.value[row.deviceNo] = ''
    }
  }).catch(() => {
    callStatusMap.value[row.deviceNo] = ''
  })
}

// 组呼呼叫
function handleTeamCall(row) {
  callStatusMap.value[row.deviceNos || row.id] = '呼叫中'
  createTeamCall({
    groupId: row.id,
    hatNumber: row.deviceNos || '',
    participant: row.userNames || ''
  }).then(res => {
    if (res.code === 200) {
      currentRecordId.value = res.data?.id
      videoTitle.value = '呼叫详情'
      videoDeviceNo.value = row.deviceNos || ''
      videoUserName.value = row.userNames || row.name
      const credentials = extractAgoraCredentials(res.data)
      if (credentials?.agoraAppId) {
        agoraCredentials.value = credentials
        openVideo.value = true
      } else {
        proxy.$modal.msgWarning('未获取到音视频凭证，仅创建了对讲记录')
      }
      callStatusMap.value[row.deviceNos || row.id] = '对讲中'
    } else {
      callStatusMap.value[row.deviceNos || row.id] = ''
    }
  }).catch(() => {
    callStatusMap.value[row.deviceNos || row.id] = ''
  })
}

// 群呼选择/取消选择
function handleBroadcastSelect(row) {
  const idx = selectedDeviceNos.value.indexOf(row.deviceNo)
  if (idx > -1) {
    selectedDeviceNos.value.splice(idx, 1)
  } else {
    selectedDeviceNos.value.push(row.deviceNo)
  }
}

// 群呼确认呼叫
function handleBroadcastCall() {
  if (selectedDeviceNos.value.length < 2) {
    proxy.$modal.msgWarning('请至少选择2个人员进行群呼')
    return
  }
  const selectedRows = broadcastList.value.filter(item => selectedDeviceNos.value.includes(item.deviceNo))
  const hatNumbers = selectedRows.map(item => item.deviceNo).join(',')
  const participants = selectedRows.map(item => item.userName).join(',')
  selectedRows.forEach(item => {
    callStatusMap.value[item.deviceNo] = '呼叫中'
  })
  createGroupCall({ hatNumber: hatNumbers, participant: participants }).then(res => {
    if (res.code === 200) {
      currentRecordId.value = res.data?.id
      videoTitle.value = '呼叫详情'
      videoDeviceNo.value = hatNumbers
      videoUserName.value = participants
      const credentials = extractAgoraCredentials(res.data)
      if (credentials?.agoraAppId) {
        agoraCredentials.value = credentials
        openVideo.value = true
      } else {
        proxy.$modal.msgWarning('未获取到音视频凭证，仅创建了对讲记录')
      }
      selectedRows.forEach(item => {
        callStatusMap.value[item.deviceNo] = '对讲中'
      })
      selectedDeviceNos.value = []
    } else {
      selectedRows.forEach(item => {
        callStatusMap.value[item.deviceNo] = ''
      })
    }
  }).catch(() => {
    selectedRows.forEach(item => {
      callStatusMap.value[item.deviceNo] = ''
    })
  })
}

// 跳转到 intercom 页面
function goToIntercom() {
  router.push('/intercom')
}

function goToSos() {
  router.push('/sos')
}

// ===== ECharts 图表 =====
const alarmStatsRef = ref(null)
const intercomStatsRef = ref(null)
const ttsStatsRef = ref(null)

const { setOptions: setAlarmStatsOptions, resize: resizeAlarmStats } = useECharts(alarmStatsRef)
const { setOptions: setIntercomStatsOptions, resize: resizeIntercomStats } = useECharts(intercomStatsRef)
const { setOptions: setTtsStatsOptions, resize: resizeTtsStats } = useECharts(ttsStatsRef)

// 地图相关
const mapContainer = ref(null)
let mapInstance = null
let mapUtils = null

// 本地人员位置数据 - 使用配置中的中心点
const staffPositions = [
  { name: '陈明辉', coord: [117.144732, 36.663887], status: 'online' },
  { name: '刘建国', coord: [117.154732, 36.673887], status: 'online' },
  { name: '王志刚', coord: [117.134732, 36.653887], status: 'busy' },
  { name: '张伟', coord: [117.164732, 36.683887], status: 'offline' },
  { name: '李俊', coord: [117.124732, 36.643887], status: 'online' },
  { name: '周强', coord: [117.174732, 36.693887], status: 'busy' }
]

// 公共颜色
const colors = {
  cyan: '#148b98',
  blue: '#1765d1',
  green: '#15845c',
  yellow: '#ad770d',
  orange: '#b45309',
  red: '#c43c43',
  purple: '#8d7bc0'
}

const chartPalette = [colors.blue, colors.green, colors.yellow, colors.red, colors.cyan, colors.purple, colors.orange]
const tooltipStyle = { confine: true, backgroundColor: 'rgba(255,255,255,0.98)', borderColor: '#e2e8f0', textStyle: { color: '#172b45' } }
const axisLabelStyle = { color: '#52647a', fontSize: 11 }
const splitLineStyle = { lineStyle: { color: 'rgba(158,171,185,0.12)' } }

function getLast7DaysDates() {
  const dates = []
  const now = new Date()
  for (let i = 6; i >= 0; i--) {
    const d = new Date(now)
    d.setDate(d.getDate() - i)
    dates.push({
      key: `${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`,
      full: `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
    })
  }
  return dates
}

function formatDateShort(dateStr) {
  if (!dateStr) return ''
  return dateStr.slice(5, 10)
}

function countByDateAndType(records, dateField, typeField, dates, typeValue) {
  const map = {}
  dates.forEach(d => { map[d.key] = 0 })
  records.forEach(r => {
    const dateKey = formatDateShort(r[dateField])
    const match = dates.find(d => d.key === dateKey)
    if (match && (!typeValue || r[typeField] === typeValue)) {
      map[match.key] = (map[match.key] || 0) + 1
    }
  })
  return dates.map(d => map[d.key] || 0)
}

function loadChartStats() {
  const dates = getLast7DaysDates()
  const startDate = dates[0].full + ' 00:00:00'
  const endDate = dates[dates.length - 1].full + ' 23:59:59'
  const dateLabels = dates.map(d => d.key)

  // 告警统计
  listAlarmPage({ current: 1, size: 1000, startTimeFrom: startDate, startTimeTo: endDate }).then(res => {
    const records = res.data?.records || []
    // 使用字典中的告警类型
    const alarmTypes = (alarm_type.value || []).map((dict, index) => ({
      name: dict.label,
      type: dict.value,
      color: chartPalette[index % chartPalette.length]
    }))
    // 如果没有字典数据，使用默认类型
    if (alarmTypes.length === 0) {
      alarmTypes.push(
        { name: '静默告警', type: 'silent', color: colors.red },
        { name: '脱帽告警', type: 'helmet_off', color: colors.yellow },
        { name: '跌落告警', type: 'fall', color: colors.blue },
        { name: 'SOS告警', type: 'sos', color: colors.green }
      )
    }
    setAlarmStatsOptions({
      animation: !reducedMotion,
      tooltip: { trigger: 'axis', ...tooltipStyle },
      legend: { tooltip: { show: true }, type: 'scroll', top: 4, left: 12, right: 12, textStyle: { color: '#52647a', fontSize: 11 }, pageIconColor: '#1765d1', pageTextStyle: { color: '#52647a' }, itemWidth: 10, itemHeight: 10, padding: 0 },
      grid: { left: 12, right: 12, top: 38, bottom: 8, containLabel: true },
      xAxis: { type: 'category', data: dateLabels, axisLine: { lineStyle: { color: 'rgba(158,171,185,0.22)' } }, axisLabel: axisLabelStyle, axisTick: { show: false } },
      yAxis: { type: 'value', axisLine: { show: false }, axisLabel: axisLabelStyle, splitLine: splitLineStyle },
      series: alarmTypes.map(at => ({
        name: at.name,
        type: 'line',
        smooth: true,
        symbol: 'circle',
        symbolSize: 6,
        lineStyle: { color: at.color, width: 2 },
        itemStyle: { color: at.color },
        data: countByDateAndType(records, 'alarmStartTime', 'alarmType', dates, at.type)
      }))
    })
  }).catch(() => { chartErrors.value.alarm = true }).finally(() => { chartLoading.value.alarm = false })

  // 对讲统计
  listIntercomRecord({ current: 1, size: 1000, startTimeFrom: startDate, startTimeTo: endDate }).then(res => {
    const records = res.data?.records || []
    const types = [
      { name: '单呼对讲', type: '01', color: colors.blue },
      { name: '群呼对讲', type: '03', color: colors.green },
      { name: '组呼对讲', type: '02', color: colors.purple }
    ]
    setIntercomStatsOptions({
      animation: !reducedMotion,
      tooltip: { trigger: 'axis', ...tooltipStyle },
      legend: { tooltip: { show: true }, type: 'scroll', top: 4, left: 12, right: 12, textStyle: { color: '#52647a', fontSize: 11 }, pageIconColor: '#1765d1', pageTextStyle: { color: '#52647a' }, itemWidth: 10, itemHeight: 10, padding: 0 },
      grid: { left: 12, right: 12, top: 38, bottom: 8, containLabel: true },
      xAxis: { type: 'category', data: dateLabels, axisLine: { lineStyle: { color: 'rgba(158,171,185,0.22)' } }, axisLabel: axisLabelStyle, axisTick: { show: false } },
      yAxis: { type: 'value', axisLine: { show: false }, axisLabel: axisLabelStyle, splitLine: splitLineStyle },
      series: types.map(t => ({
        name: t.name,
        type: 'bar',
        barWidth: '20%',
        itemStyle: { color: t.color, borderRadius: [2, 2, 0, 0] },
        data: countByDateAndType(records, 'startTime', 'intercomType', dates, t.type)
      }))
    })
  }).catch(() => { chartErrors.value.intercom = true }).finally(() => { chartLoading.value.intercom = false })

  // 语音合成统计
  listTtsRecord({ current: 1, size: 1000, sendTimeFrom: startDate, sendTimeTo: endDate }).then(res => {
    const records = res.data?.records || []
    const types = [
      { name: '文字语音合成单播', type: '01', color: colors.red },
      { name: '文字语音合成群播', type: '02', color: colors.yellow },
      { name: '文字语音合成组播', type: '03', color: colors.blue }
    ]
    setTtsStatsOptions({
      animation: !reducedMotion,
      tooltip: { trigger: 'axis', ...tooltipStyle },
      legend: { tooltip: { show: true }, type: 'scroll', top: 4, left: 12, right: 12, textStyle: { color: '#52647a', fontSize: 11 }, pageIconColor: '#1765d1', pageTextStyle: { color: '#52647a' }, itemWidth: 10, itemHeight: 10, padding: 0 },
      grid: { left: 12, right: 12, top: 38, bottom: 8, containLabel: true },
      xAxis: { type: 'category', data: dateLabels, axisLine: { lineStyle: { color: 'rgba(158,171,185,0.22)' } }, axisLabel: axisLabelStyle, axisTick: { show: false } },
      yAxis: { type: 'value', axisLine: { show: false }, axisLabel: axisLabelStyle, splitLine: splitLineStyle },
      series: types.map(t => ({
        name: t.name,
        type: 'bar',
        barWidth: '18%',
        itemStyle: { color: t.color, borderRadius: [2, 2, 0, 0] },
        data: countByDateAndType(records, 'sendTime', 'broadcastType', dates, t.type)
      }))
    })
  }).catch(() => { chartErrors.value.tts = true }).finally(() => { chartLoading.value.tts = false })
}

function initCharts() {
  loadChartStats()
}

function initMap() {
  if (!mapContainer.value) return
  
  // 强制延迟初始化，确保 DOM 已渲染
  mapTimer = setTimeout(() => {
    const utils = useMap()
    mapUtils = utils
    utils.initMap(mapContainer.value)
    mapInstance = utils.map.value
    
    // 再延迟一下添加标记，确保地图完全初始化
    markerTimer = setTimeout(() => {
      // 添加人员标记
      staffPositions.forEach(staff => {
        mapUtils.addMarker(staff.coord)
      })
    }, 300)
  }, 100)
}

// ===== 生命周期 =====
onMounted(() => {
  updateTime()
  timer = setInterval(updateTime, 1000)

  // 加载对讲数据
  loadAlarmList()
  loadHelmetList()
  loadHelmetAllList().catch(() => {}).finally(() => { loadGroupList() })

  nextTick(() => {
    initCharts()
    initMap()
    layoutObserver = new ResizeObserver(resizePanels)
    ;[mapContainer.value, alarmStatsRef.value, intercomStatsRef.value, ttsStatsRef.value].forEach(el => {
      if (el) layoutObserver.observe(el)
    })
  })
})

onBeforeUnmount(() => {
  if (timer) clearInterval(timer)
  clearTimeout(mapTimer)
  clearTimeout(markerTimer)
  layoutObserver?.disconnect()
  cancelAnimationFrame(layoutFrame)
  if (mapUtils) {
    mapUtils.cleanup()
  }
})
</script>

<style lang="scss" scoped src="./screen.scss"></style>
