import request from '@/utils/request'

export function listPersonLocations(params) {
  return request({ url: '/api/v1/locations/people', method: 'get', params })
}

export function getPersonLocation(id) {
  return request({ url: '/api/v1/locations/people/' + id, method: 'get' })
}

export function listPersonTracks(id, params) {
  return request({ url: '/api/v1/locations/people/' + id + '/tracks', method: 'get', params })
}

export function locationQualityLabel(q) {
  const map = { ok: '有效', stale: '陈旧', unknown: '未知' }
  return map[q] || q || '未知'
}
