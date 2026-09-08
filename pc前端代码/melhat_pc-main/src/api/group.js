import request from "@/utils/request";

// 分组列表
export function groupList(query) {
  return request({
    url: "/hat/group/info",
    method: "get",
    params: query,
  });
}

// 分组信息（POST）
export function groupInfo(data) {
  return request({
    url: "/hat/group/info",
    method: "post",
    data: data,
  });
}

// 编辑分组信息（PUT）
export function groupInfoUpdate(data) {
  return request({
    url: "/hat/group/info",
    method: "put",
    data: data,
  });
}

// 删除分组信息（DELETE）
export function groupInfoDelete(id) {
  return request({
    url: "/hat/group/info/" + id,
    method: "delete",
  });
}

// 查询分组详情（GET）
export function groupInfoDetail(id) {
  return request({
    url: "/hat/group/info/" + id,
    method: "get",
  });
}
