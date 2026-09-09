import request from '@/utils/request'

export function listWorkTasks(params) {
  return request({ url: '/api/v1/work-tasks', method: 'get', params })
}

export function listMyWorkTasks(params) {
  return request({ url: '/api/v1/work-tasks/mine', method: 'get', params })
}

export function getWorkTask(id) {
  return request({ url: '/api/v1/work-tasks/' + id, method: 'get' })
}

export function createWorkTask(data) {
  return request({ url: '/api/v1/work-tasks', method: 'post', data })
}

export function updateWorkTask(id, data) {
  return request({ url: '/api/v1/work-tasks/' + id, method: 'put', data })
}

export function addWorkTaskMembers(id, data) {
  return request({ url: '/api/v1/work-tasks/' + id + '/members', method: 'post', data })
}

export function startWorkTask(id, data) {
  return request({ url: '/api/v1/work-tasks/' + id + '/start', method: 'post', data })
}

export function pauseWorkTask(id, data) {
  return request({ url: '/api/v1/work-tasks/' + id + '/pause', method: 'post', data })
}

export function endWorkTask(id, data) {
  return request({ url: '/api/v1/work-tasks/' + id + '/end', method: 'post', data })
}

export function listWorkTaskEvents(id) {
  return request({ url: '/api/v1/work-tasks/' + id + '/events', method: 'get' })
}

export function assignEventTask(eventId, data) {
  return request({ url: '/api/v1/events/' + eventId + '/task', method: 'post', data })
}

export function workTypeLabel(type) {
  const map = { patrol: '巡检', height: '高处', other: '其他' }
  return map[type] || type || '-'
}

export function taskStatusLabel(status) {
  const map = {
    draft: '草稿',
    ready: '就绪',
    in_progress: '进行中',
    paused: '已暂停',
    ended: '已结束'
  }
  return map[status] || status || '-'
}

export function ticketStatusLabel(status) {
  const map = { none: '不要求票', provided: '已填票号', unverified: '待核实' }
  return map[status] || status || '-'
}

export function equipmentResultLabel(result) {
  const map = { missing: '缺装备', ok: '有效', unknown: '未知' }
  return map[result] || result || '-'
}
