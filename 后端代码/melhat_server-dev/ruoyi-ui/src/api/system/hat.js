import request from '@/utils/request'

// 查询安全帽列表
export function listHat(query) {
  return request({
    url: '/system/hat/list',
    method: 'get',
    params: query
  })
}

// 查询安全帽详细
export function getHat(id) {
  return request({
    url: '/system/hat/' + id,
    method: 'get'
  })
}

// 新增安全帽
export function addHat(data) {
  return request({
    url: '/system/hat',
    method: 'post',
    data: data
  })
}

// 修改安全帽
export function updateHat(data) {
  return request({
    url: '/system/hat',
    method: 'put',
    data: data
  })
}

// 删除安全帽
export function delHat(id) {
  return request({
    url: '/system/hat/' + id,
    method: 'delete'
  })
}
