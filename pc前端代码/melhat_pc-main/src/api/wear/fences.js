import request from '@/utils/request'

export function listFences(params) {
  return request({ url: '/api/v1/fences', method: 'get', params })
}

export function getFence(id) {
  return request({ url: '/api/v1/fences/' + id, method: 'get' })
}

export function createFence(data) {
  return request({ url: '/api/v1/fences', method: 'post', data })
}

export function updateFence(id, data) {
  return request({ url: '/api/v1/fences/' + id, method: 'put', data })
}

export function setFenceEnabled(id, data) {
  return request({ url: '/api/v1/fences/' + id + '/enabled', method: 'put', data })
}

export function evaluateFence(data) {
  return request({ url: '/api/v1/fences/evaluate', method: 'post', data })
}
