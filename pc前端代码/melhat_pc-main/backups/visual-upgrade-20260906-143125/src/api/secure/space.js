import request from '@/utils/request'

// 查询受限空间配置列表
export function listSpace(query) {
  return request({
    url: '/system/space/list',
    method: 'get',
    params: query
  })
}

// 查询受限空间配置详细
export function getSpace(id) {
  return request({
    url: '/system/space/' + id,
    method: 'get'
  })
}

// 新增受限空间配置
export function addSpace(data) {
  return request({
    url: '/system/space',
    method: 'post',
    data: data
  })
}

// 修改受限空间配置
export function updateSpace(data) {
  return request({
    url: '/system/space',
    method: 'put',
    data: data
  })
}

// 删除受限空间配置
export function delSpace(id) {
  return request({
    url: '/system/space/' + id,
    method: 'delete'
  })
}
