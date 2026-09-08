import request from '@/utils/request'

// 查询大屏模块配置列表
export function listModule(query) {
  return request({
    url: '/system/module/list',
    method: 'get',
    params: query
  })
}

// 查询大屏模块配置详细
export function getModule(id) {
  return request({
    url: '/system/module/' + id,
    method: 'get'
  })
}

// 新增大屏模块配置
export function addModule(data) {
  return request({
    url: '/system/module',
    method: 'post',
    data: data
  })
}

// 修改大屏模块配置
export function updateModule(data) {
  return request({
    url: '/system/module',
    method: 'put',
    data: data
  })
}

// 删除大屏模块配置
export function delModule(id) {
  return request({
    url: '/system/module/' + id,
    method: 'delete'
  })
}
