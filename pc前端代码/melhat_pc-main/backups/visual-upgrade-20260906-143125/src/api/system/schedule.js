import request from '@/utils/request'

// 查询任务计划列表
export function listSchedule(query) {
  return request({
    url: '/task/schedule/list',
    method: 'get',
    params: query
  })
}

// 查询任务计划详细
export function getSchedule(id) {
  return request({
    url: '/task/schedule/' + id,
    method: 'get'
  })
}

// 新增任务计划

export function addSchedule(data) {
  return request({
    url: '/task/schedule',
    method: 'post',
    data: data
  })
}

// 修改任务计划

export function updateSchedule(data) {
  return request({
    url: '/task/schedule',
    method: 'put',
    data: data
  })
}

// 删除任务计划

export function delSchedule(id) {
  return request({
    url: '/task/schedule/' + id,
    method: 'delete'
  })
}

//查询计划下任务
export function getTasksSchedule(id) {
  return request({
    url: '/task/schedule/tasksSchedule/' + id,
    method: 'get'
  })
}
