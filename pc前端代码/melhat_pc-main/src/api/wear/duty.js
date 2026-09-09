import request from '@/utils/request'

export function dutySummary() {
  return request({ url: '/api/v1/duty/summary', method: 'get' })
}

export function listDutyOperators() {
  return request({ url: '/api/v1/duty/operators', method: 'get' })
}

export function listHandovers() {
  return request({ url: '/api/v1/duty/handovers', method: 'get' })
}

export function createHandover(data) {
  return request({ url: '/api/v1/duty/handovers', method: 'post', data })
}

export function confirmHandover(id) {
  return request({ url: '/api/v1/duty/handovers/' + id + '/confirm', method: 'post' })
}
