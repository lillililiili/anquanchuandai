import request from '@/utils/request'

// 查询现场检查列表
export function listInspection(query) {
  return request({
    url: '/system/inspection/list',
    method: 'get',
    params: query
  })
}

// 查询现场检查详细
export function getInspection(id) {
  return request({
    url: '/system/inspection/' + id,
    method: 'get'
  })
}

// 新增现场检查
export function addInspection(data) {
  return request({
    url: '/system/inspection',
    method: 'post',
    data: data
  })
}

// 修改现场检查
export function updateInspection(data) {
  return request({
    url: '/system/inspection',
    method: 'put',
    data: data
  })
}

// 删除现场检查
export function delInspection(id) {
  return request({
    url: '/system/inspection/' + id,
    method: 'delete'
  })
}

// 查询部门下拉树结构
export function deptTreeSelect() {
  return request({
    url: '/system/user/deptTree',
    method: 'get'
  })
}

//查询部门下员工
export function getDepartment(id) {
  return request({
    url: '/todo/tasks/getDepartment/' + id,
    method: 'get'
  })
}

// 分发
export function getHandOut(data) {
  return request({
    url: '/system/inspection/getHandOut',
    method: 'post',
    data: data
  })
  }
