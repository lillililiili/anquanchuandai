import request from "@/utils/request";

// 分页查询文件记录
export function getFileRecordPage(query) {
  return request({
    url: "/hat/file/record/page",
    method: "get",
    params: query,
  });
}
