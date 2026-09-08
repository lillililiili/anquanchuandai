import request from '@/utils/request'

// 查询缺陷隐患违章列表
export function listProblem(query) {
  return request({
    url: '/system/problem/list',
    method: 'get',
    params: query
  })
}

// 查询缺陷隐患违章详细
export function getProblem(id) {
  return request({
    url: '/system/problem/' + id,
    method: 'get'
  })
}

// 新增缺陷隐患违章
export function addProblem(data) {
  return request({
    url: '/system/problem',
    method: 'post',
    data: data
  })
}

// 修改缺陷隐患违章
export function updateProblem(data) {
  return request({
    url: '/system/problem',
    method: 'put',
    data: data
  })
}

// 删除缺陷隐患违章
export function delProblem(id) {
  return request({
    url: '/system/problem/' + id,
    method: 'delete'
  })
}

// 分发缺陷隐患违章
export function getHandOut(data) {
  return request({
    url: '/system/problem/getHandOut',
    method: 'post',
    data: data
  })
  }

  //挂起操作
  // 新增缺陷隐患违章
export function getHandUp(data) {
  return request({
    url: '/system/problem/getHandUp',
    method: 'put',
    data: data
  })
  }