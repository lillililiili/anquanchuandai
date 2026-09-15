import request from '@/utils/request'

export function listDevices(params) {
  return request({ url: '/api/v1/devices', method: 'get', params })
}

export function getDevice(id) {
  return request({ url: '/api/v1/devices/' + id, method: 'get' })
}

export function createDevice(data) {
  return request({ url: '/api/v1/devices', method: 'post', data })
}

export function updateDevice(id, data) {
  return request({ url: '/api/v1/devices/' + id, method: 'put', data })
}

export function assignDeviceSite(id, data) {
  return request({ url: '/api/v1/devices/' + id + '/site', method: 'put', data })
}

export function changeDeviceAssetStatus(id, data) {
  return request({ url: '/api/v1/devices/' + id + '/asset-status', method: 'put', data })
}

export function listProductModels(params) {
  return request({ url: '/api/v1/product-models', method: 'get', params })
}

export function getProductModel(id) {
  return request({ url: '/api/v1/product-models/' + id, method: 'get' })
}

export function createProductModel(data) {
  return request({ url: '/api/v1/product-models', method: 'post', data })
}

export function updateProductModel(id, data) {
  return request({ url: '/api/v1/product-models/' + id, method: 'put', data })
}

export function changeProductModelStatus(id, data) {
  return request({ url: '/api/v1/product-models/' + id + '/status', method: 'put', data })
}

export function listDeviceSamples(id) {
  return request({ url: '/api/v1/devices/' + id + '/samples', method: 'get' })
}

export function listDeviceIngest(id) {
  return request({ url: '/api/v1/devices/' + id + '/ingest', method: 'get' })
}

export function replayIngest(data) {
  return request({ url: '/api/v1/ingest/replay', method: 'post', data })
}

export function supportsCapability(device, feature) {
  const caps = (device && device.capabilities) || {}
  const lists = [].concat(caps.actions || [], caps.attributes || [], caps.events || [])
  return lists.indexOf(feature) !== -1
}

export function connectionLabel(row) {
  if (!row) return '未知'
  if (row.connectionQuality === 'stale') return '陈旧'
  if (row.connectionQuality === 'ok') return '有效'
  if (row.online == null || row.online === '') return '未知'
  return '未知'
}
