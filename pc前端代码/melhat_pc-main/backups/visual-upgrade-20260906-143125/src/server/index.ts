import { getSocketUrl } from '@/utils/websocketUrl'
import router from '@/router'

let instance: WebSocket | null = null
let wsUserId = ''
let wsType = 1
let reconnectAttempts = 0
const MAX_RECONNECT_ATTEMPTS = 5
const RECONNECT_DELAY = 3000

export function isWsConnected(): boolean {
  return instance && instance.readyState === WebSocket.OPEN
}

export function closeWebSocket() {
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
  wsUserId = id
  wsType = type
  reconnectAttempts = 0
  createWebSocket(id, type)
  return instance
}

function createWebSocket(id: string, type: number) {
  console.log('WebSocket 连接初始化')
  const url = getSocketUrl(`ws/${id}/${type}`)
  instance = new WebSocket(url)
  instance.onopen = handleOpen
  instance.onclose = handleClose
  instance.onmessage = handleMessage
  instance.onerror = handleError
}

function handleOpen() {
  console.log('WebSocket 连接成功')
  reconnectAttempts = 0
}

function handleClose() {
  console.log('WebSocket 连接关闭')
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

function navigateToSosPage(alarmData: any) {
  router.push({
    path: '/sos',
    query: {
      showDetail: 'true',
      alarmData: JSON.stringify(alarmData)
    }
  })
}