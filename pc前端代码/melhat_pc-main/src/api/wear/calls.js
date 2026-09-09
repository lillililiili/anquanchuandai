import request from '@/utils/request'

export function startCall(data) {
  return request({ url: '/api/v1/calls', method: 'post', data })
}

export function getCall(id) {
  return request({ url: '/api/v1/calls/' + id, method: 'get' })
}

export function getCallCredentials(id) {
  return request({ url: '/api/v1/calls/' + id + '/credentials', method: 'get' })
}

export function joinCall(id, data) {
  return request({ url: '/api/v1/calls/' + id + '/joined', method: 'post', data })
}

export function endCall(id) {
  return request({ url: '/api/v1/calls/' + id + '/end', method: 'post' })
}

export function listEventCalls(eventId) {
  return request({ url: '/api/v1/events/' + eventId + '/calls', method: 'get' })
}

export function sendTts(data) {
  return request({ url: '/api/v1/commands/tts', method: 'post', data })
}

export function callStatusLabel(status) {
  const map = {
    requesting: '请求中',
    offered: '待加入',
    connected: '已接通',
    ended: '已结束',
    failed: '失败',
    timed_out: '待核验'
  }
  return map[status] || status || '-'
}

export function isCallConnected(status) {
  return status === 'connected'
}
