import request from "@/utils/request";

// 查询任务计划列表
export function listSchedule(query) {
  return request({
    url: "/task/schedule/list",
    method: "get",
    params: query,
  });
}

// 查询任务计划详细
export function getSchedule(id) {
  return request({
    url: "/task/schedule/" + id,
    method: "get",
  });
}

// 新增任务计划
export function addSchedule(data) {
  return request({
    url: "/task/schedule/add",
    method: "post",
    data: data,
  });
}

// 修改任务计划
export function updateSchedule(data) {
  return request({
    url: "/task/schedule",
    method: "put",
    data: data,
  });
}

// 删除任务计划

export function delSchedule(id) {
  return request({
    url: "/task/schedule/" + id,
    method: "delete",
  });
}

//查询计划下任务
export function getTasksSchedule(id, page, name) {
  return request({
    url: "/task/schedule/tasksSchedule/" + id,
    method: "get",
    params: {
      ...page,
      name,
    },
  });
}

export function getTasksScheduleNew(params) {
  return request({
    url: "/task/schedule/tasksBySchedule",
    method: "post",
    data: params,
  });
}

//添加任务
export function addNewTasks(data) {
  return request({
    url: "/todo/tasks/addnew",
    method: "post",
    data: data,
  });
}

// 查询用户列表
export function listUser(query) {
  return request({
    url: "/system/user/list",
    method: "get",
    params: query,
  });
}

// 查询部门下拉树结构
export function deptTreeSelect() {
  return request({
    url: "/system/user/deptTree",
    method: "get",
  });
}

//查询部门下员工
export function getDepartment(id, params) {
  return request({
    url: "/todo/tasks/getDepartment/" + id,
    method: "get",
    params,
  });
}

export function getHandOut(data) {
  return request({
    url: "/todo/tasks/getHandOut",
    method: "post",
    data: data,
  });
}

//添加维修准备计划任务
export function getActTasksByIds(taskIds) {
  return request({
    url: "/todo/tasks/getTasksByIds",
    method: "get",
    params: { taskIds },
  });
}
