import request from "@/utils/request";

// 查询任务列表
export function listTasks(query) {
  return request({
    url: "/todo/tasks/list",
    method: "get",
    params: query,
  });
}
export function todoTaskList(query) {
  return request({
    url: "/todo/tasks/todoTaskList",
    method: "get",
    params: query,
  });
}
export function finishTaskList(query) {
  return request({
    url: "/todo/tasks/finishTaskList",
    method: "get",
    params: query,
  });
}
// 查询任务详细
export function getTasks(taskId) {
  return request({
    url: "/todo/tasks/look/" + taskId,
    method: "get",
  });
}

// 新增任务
export function addTasks(data) {
  return request({
    url: "/todo/tasks",
    method: "post",
    data: data,
  });
}

// 修改任务
export function updateTasks(data) {
  return request({
    url: "/todo/tasks/edit",
    method: "put",
    data: data,
  });
}

// 删除任务
export function delTasks(taskId) {
  return request({
    url: "/todo/tasks/" + taskId,
    method: "delete",
  });
}

//执行任务
export function executeTasks(data) {
  return request({
    url: "/todo/tasks/execute",
    method: "post",
    data: data,
  });
}
//审核任务
export function checkTask(data) {
  return request({
    url: "/todo/tasks/checkTask",
    method: "post",
    data: data,
  });
}
//审核
export function auditTasks(data) {
  return request({
    url: "/todo/tasks/auditTasks",
    method: "post",
    data: data,
  });
}
//验收
export function yanshouTasks(data) {
  return request({
    url: "/todo/tasks/yanshouTasks",
    method: "post",
    data: data,
  });
}
//打回重写执行
export function execution(taskId) {
  return request({
    url: "/todo/tasks/execution/" + taskId,
    method: "get",
  });
}
//回显图片
export function echo(taskId) {
  return request({
    url: "/todo/tasks/getEcho/" + taskId,
    method: "get",
  });
}

//开始执行
export function startExecute(taskId) {
  return request({
    url: "/todo/tasks/startExecute/" + taskId,
    method: "get",
  });
}

//告警列表
export function taskWarnList(query) {
  return request({
    url: "/todo/tasks/taskWarnList",
    method: "get",
    params: query,
  });
}

//退回任务
export function getReturn(taskId) {
  return request({
    url: "/todo/tasks/getReturn/" + taskId,
    method: "get",
  });
}

//根据任务id获取任务下的执行人员帽子信息
export function listUserByTaskId(query) {
  return request({
    url: "/todo/tasks/listUserByTaskId",
    method: "get",
    params: query,
  });
}
//报废任务
export function getScrap(taskId) {
  return request({
    url: "/todo/tasks/getScrap/" + taskId,
    method: "get",
  });
}
//查看
export function openRtsp(data) {
  return request({
    url: "/api/melhat/openRtsp",
    method: "get",
    params: data,
  });
}

//设备查询
export function getDevice() {
  return request({
    url: "/device/devices/list",
    method: "get",
  });
}

//添加巡检计划
export function getInspection(data) {
  return request({
    url: "/system/configs/add",
    method: "post",
    data: data,
  });
}

//查询巡检计划
export function findConfig(data) {
  return request({
    url: "/system/configs/list",
    method: "get",
    data: data,
  });
}

export function queryInspectionRecord(rid) {
  return request({
    url: "/system/records/InspectionQueryResultById/" + rid,
    method: "get",
  });
}

// 修改任务
export function updateWXTasks(data) {
  return request({
    url: "/todo/tasks/editnew",
    method: "put",
    data: data,
  });
}

// 新增任务
export function addNewTasks(data) {
  return request({
    url: "/todo/tasks/addnew",
    method: "post",
    data: data,
  });
}

//查询子任务
export function subTaskList(query) {
  return request({
    url: "/subTask/list",
    method: "get",
    params: query,
  });
}

// 新增子任务
export function addSubTask(data) {
  return request({
    url: "/subTask/add",
    method: "post",
    data: data,
  });
}

// 修改子任务
export function updateSubTask(data) {
  return request({
    url: "/subTask/edit",
    method: "put",
    data: data,
  });
}

//删除子任务
export function delSubTask(taskId) {
  return request({
    url: "/subTask/remove/" + taskId,
    method: "delete",
  });
}

// 查询巡检记录
export function queryAppPolling(id) {
  return request({
    url: "/todo/tasks/appPolling/" + id,
    method: "get",
  });
}

export function queryTaskById(id) {
  return request({
    url: "/todo/tasks/appPolling/" + id,
    method: "get",
  });
}
