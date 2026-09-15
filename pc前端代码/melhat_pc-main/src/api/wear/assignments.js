import request from '@/utils/request'

export function listAssignments(params) {
  return request({ url: '/api/v1/assignments', method: 'get', params })
}

export function issueAssignment(data) {
  return request({ url: '/api/v1/assignments', method: 'post', data })
}

export function returnAssignment(id, data) {
  return request({ url: '/api/v1/assignments/' + id + '/return', method: 'post', data })
}

export function recoverAssignment(id, data) {
  return request({ url: '/api/v1/assignments/' + id + '/recover', method: 'post', data })
}

export function getDeviceAssignment(deviceId) {
  return request({ url: '/api/v1/devices/' + deviceId + '/assignment', method: 'get' })
}

export function listDeviceAssignments(deviceId) {
  return request({ url: '/api/v1/devices/' + deviceId + '/assignments', method: 'get' })
}

export function listPersonEquipment(personId) {
  return request({ url: '/api/v1/people/' + personId + '/equipment', method: 'get' })
}

export function listPersonAssignments(personId) {
  return request({ url: '/api/v1/people/' + personId + '/assignments', method: 'get' })
}

export function newIdempotencyKey() {
  if (typeof crypto !== 'undefined' && crypto.randomUUID) {
    return crypto.randomUUID()
  }
  return 'k-' + Date.now() + '-' + Math.random().toString(16).slice(2)
}
