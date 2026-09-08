import request from '@/utils/request'

// 查询报警列表
export function listSos(query) {
  return request({
    url: '/system/sos/list',
    method: 'get',
    params: query
  })
}

// 查询报警详细
export function getSos(id) {
  return request({
    url: '/system/sos/' + id,
    method: 'get'
  })
}

// 新增报警
export function addSos(data) {
  return request({
    url: '/system/sos',
    method: 'post',
    data: data
  })
}

// 修改报警
export function updateSos(data) {
  return request({
    url: '/system/sos',
    method: 'put',
    data: data
  })
}

// 删除报警
export function delSos(id) {
  return request({
    url: '/system/sos/' + id,
    method: 'delete'
  })
}
