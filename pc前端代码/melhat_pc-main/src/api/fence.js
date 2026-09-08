import request from "@/utils/request";

// 分页查询电子围栏
export function getFencePage(query) {
  return request({
    url: "/hat/electronic/fence/page",
    method: "get",
    params: query,
  });
}

// 新增电子围栏
export function addFence(data) {
  return request({
    url: "/hat/electronic/fence",
    method: "post",
    data: data,
  });
}

// 修改电子围栏
export function updateFence(data) {
  return request({
    url: "/hat/electronic/fence",
    method: "put",
    data: data,
  });
}

// 查询电子围栏详情
export function getFence(id) {
  return request({
    url: "/hat/electronic/fence/" + id,
    method: "get",
  });
}

// 删除电子围栏
export function deleteFence(id) {
  return request({
    url: "/hat/electronic/fence/" + id,
    method: "delete",
  });
}

// 报警列表查询
export function getFenceAlarmPage(query) {
  return request({
    url: "/hat/fence/alarm/page",
    method: "get",
    params: query,
  });
}
