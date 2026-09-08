import request from "@/utils/request";

// 头盔列表
export function hatList(query) {
  return request({
    url: "/aip/head/band/list",
    method: "get",
    params: query,
  });
}

// 头盔绑定
export function hatBind(data) {
  return request({
    url: "/aip/head/band/edit",
    method: "put",
    data: data,
  });
}

// 头盔详情
export function hatDetail(id) {
  return request({
    url: "/aip/head/band/" + id,
    method: "get",
  });
}

// 同步头盔信息
export function hatSync(data) {
  return request({
    url: "/aip/head/band/sync/device/info",
    method: "get",
  });
}

// 查询安全帽信息列表（分页）
export function hatSafetyInfoPage(query) {
  return request({
    url: "/hat/safety/info/page",
    method: "get",
    params: query,
  });
}

// 查询安全帽信息列表（不分页，用于统计）
export function hatSafetyInfoList() {
  return request({
    url: "/hat/safety/info/list",
    method: "get",
  });
}

// 修改安全帽信息
export function hatSafetyInfoUpdate(data) {
  return request({
    url: "/hat/safety/info/updte",
    method: "post",
    data: data,
  });
}

// 新增安全帽信息
export function hatSafetyInfoSave(data) {
  return request({
    url: "/hat/safety/info/save",
    method: "post",
    data: data,
  });
}

// 删除安全帽信息
export function hatSafetyInfoDelete(id) {
  return request({
    url: "/hat/safety/info/" + id,
    method: "delete",
  });
}
