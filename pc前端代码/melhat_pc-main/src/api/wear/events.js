import request from '@/utils/request'

export function listEvents(params) {
  return request({ url: '/api/v1/events', method: 'get', params })
}

export function getEvent(id) {
  return request({ url: '/api/v1/events/' + id, method: 'get' })
}

export function listEventActions(id) {
  return request({ url: '/api/v1/events/' + id + '/actions', method: 'get' })
}

export function inboxCount() {
  return request({ url: '/api/v1/events/inbox/count', method: 'get' })
}

export function ackEvent(id) {
  return request({ url: '/api/v1/events/' + id + '/ack', method: 'post' })
}

export function claimEvent(id, data) {
  return request({ url: '/api/v1/events/' + id + '/claim', method: 'post', data })
}

export function handleEvent(id, data) {
  return request({ url: '/api/v1/events/' + id + '/handle', method: 'post', data })
}

export function transferEvent(id, data) {
  return request({ url: '/api/v1/events/' + id + '/transfer', method: 'post', data })
}

export function closeEvent(id, data) {
  return request({ url: '/api/v1/events/' + id + '/close', method: 'post', data })
}

export function reopenEvent(id, data) {
  return request({ url: '/api/v1/events/' + id + '/reopen', method: 'post', data })
}

export function simulateEvent(data) {
  return request({ url: '/api/v1/events/simulate', method: 'post', data })
}

export function eventTypeLabel(type) {
  const map = { sos: 'SOS', fall: '坠落', impact: '冲击', geofence: '围栏', realtime: '实时告警' }
  return map[type] || type || '-'
}

export function fenceActionLabel(action) {
  if (action === 'enter') return '进入'
  if (action === 'leave') return '离开'
  return action || ''
}

export function eventStatusLabel(status) {
  const map = {
    open: '待认领',
    claimed: '已认领',
    handling: '处置中',
    pending_review: '待复核',
    closed: '已关闭'
  }
  return map[status] || status || '-'
}
