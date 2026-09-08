import request from "@/utils/request";

// 查询任务列表
export function queryAppPolling(id) {
  return request({
    url: "/todo/tasks/appPolling/" + id,
    method: "get",
  });
}

// 当选择设备的时候，查询对应的巡检结果
export function queryResultByDeviceAndRecord(deviceId, recordId) {
  return request({
    url: `/device/devices/deviceFind/${deviceId}/${recordId}`,
    method: "get",
  });
}

// 查询巡检记录
export function queryRecord(recordId) {
  return request({
    url: `/system/record/inquireDeviceFind/${recordId}`,
    method: "get",
  });
}

// 查询巡检记录详情/设备
export function queryDevices(kks) {
  return request({
    url: `/device/devices/getDeviceByKks/${kks}`,
    method: "get",
  });
}

export function queryResultById(id) {
  return request({
    url: `/system/records/InspectionQueryResultById/${id}`,
    method: "get",
  });
}

export function queryResultByKKS(kks, taskId) {
  return request({
    url: `/system/record/kks/new`,
    method: "get",
    params: {
      kks,
      taskId,
    },
  });
}

export function queryConfigById(id, kks) {
  return request({
    url: `/system/items/config/TabInspectionItemsConfigByTaskId/${id}/${kks}`,
    method: "get",
  });
}

export function add(data) {
  return request({
    url: `/system/record/getInspectionRecord`,
    method: "post",
    data,
  });
}

export function save(data) {
  return request({
    url: `/system/record/saveDeposit`,
    method: "post",
    data,
  });
}

export function queryLatestInspectionRecord(taskId, kks) {
  return request({
    url: `/system/record/getLastRecord/${taskId}/${kks}`,
    method: "get",
  });
}

// 办理审批
export function setApprove(data) {
  return request({
    url: `/task/manage/completeTask/` + data.id,
    method: "post",
    data,
  });
}

// 新增审批配置
export function addApproveConfig(data) {
  return request({
    url: "/checkConfig/add",
    method: "post",
    data,
  });
}

// 查询审批配置列表
export function queryApproveConfig(params) {
  return request({
    url: `/checkConfig/list`,
    method: "get",
    params,
  });
}

// 删除审批配置
export function delApproveConfig(id) {
  return request({
    url: "/checkConfig/" + id,
    method: "delete",
  });
}

// 修改审批配置列表
export function editApproveConfig(data) {
  return request({
    url: `/checkConfig/edit`,
    method: "put",
    data: data,
  });
}
