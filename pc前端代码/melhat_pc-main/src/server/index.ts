import { getSocketUrl } from '@/utils/websocketUrl'
import { getToken } from '@/utils/auth'
import { ElNotification } from 'element-plus'
import router from '@/router'

let instance: WebSocket | null = null
let wsUserId = ''
let wsType = 1
let reconnectAttempts = 0
let closedByUser = false
const MAX_RECONNECT_ATTEMPTS = 5
const RECONNECT_DELAY = 3000

export function isWsConnected(): boolean {
  return instance && instance.readyState === WebSocket.OPEN
}

export function closeWebSocket() {
  closedByUser = true
  wsUserId = ''
  reconnectAttempts = MAX_RECONNECT_ATTEMPTS
  if (instance) {
    instance.close()
    instance = null
  }
}

export function sendMessage(data: string) {
  if (instance && instance.readyState === WebSocket.OPEN) {
    instance.send(data)
  }
}

export function initWebSocketServer(id = '', type = 1) {
  closedByUser = false
  wsUserId = id
  wsType = type
  reconnectAttempts = 0
  createWebSocket(id, type)
  return instance
}

function createWebSocket(id: string, type: number) {
  console.log('WebSocket 连接初始化')
  const token = getToken()
  const suffix = token ? `?token=${encodeURIComponent(token)}` : ''
  const url = getSocketUrl(`ws/${id}/${type}${suffix}`)
  instance = new WebSocket(url)
  instance.onopen = handleOpen
  instance.onclose = handleClose
  instance.onmessage = handleMessage
  instance.onerror = handleError
}

function handleOpen() {
  console.log('WebSocket 连接成功')
  reconnectAttempts = 0
  if (typeof window !== 'undefined') {
    window.dispatchEvent(new CustomEvent('wear-event-connected'))
  }
}

function handleClose() {
  console.log('WebSocket 连接关闭')
  if (closedByUser || !wsUserId) {
    return
  }
  if (reconnectAttempts < MAX_RECONNECT_ATTEMPTS) {
    reconnectAttempts++
    console.log(`尝试重连 WebSocket (${reconnectAttempts}/${MAX_RECONNECT_ATTEMPTS})`)
    setTimeout(() => {
      if (wsUserId) {
        createWebSocket(wsUserId, wsType)
      }
    }, RECONNECT_DELAY)
  }
}

function handleError() {
  console.log('WebSocket 连接错误')
}

function handleMessage(event: MessageEvent) {
  try {
    const message = JSON.parse(event.data)
    console.log('WebSocket 收到消息:', message)

    if (message.type === 'alarm' && message.data) {
      handleAlarmMessage(message.data)
    }
    if (message.type === 'wear.event') {
      handleWearEventMessage(message)
    }
  } catch (e) {
    console.error('WebSocket 消息解析失败:', e)
  }
}

export function handleAlarmMessage(alarmData: any) {
  console.log('处理告警消息:', alarmData)

  // 使用自定义告警通知组件
  if (typeof window !== 'undefined' && (window as any).showAlarmNotification) {
    (window as any).showAlarmNotification(alarmData)
  }
}

export function handleWearEventMessage(message: any) {
  if (typeof window !== 'undefined') {
    window.dispatchEvent(new CustomEvent('wear-event', { detail: message }))
  }
  ElNotification({
    title: message && message.demo ? '演示安全事件' : '安全事件',
    message: '收到新事件通知，请以列表为准',
    type: message && message.severity === 'high' ? 'error' : 'warning',
    duration: 5000,
    onClick: () => {
      router.push({ path: '/business/events' })
    }
  })
}

function navigateToSosPage(alarmData: any) {
  router.push({
    path: '/sos',
    query: {
      showDetail: 'true',
      alarmData: JSON.stringify(alarmData)
    }
  })
}