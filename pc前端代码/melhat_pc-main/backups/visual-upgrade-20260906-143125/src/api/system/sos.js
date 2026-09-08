import request from '@/utils/request';

// 查询报警列表
export function listSos(query) {
  return request({
    url: '/system/sos/list',
    method: 'get',
    params: query,
  });
}

// 查询报警详细
export function getSos(id) {
  return request({
    url: '/system/sos/' + id,
    method: 'get',
  });
}

// 新增报警
export function addSos(data) {
  return request({
    url: '/system/sos',
    method: 'post',
    data: data,
  });
}

// 修改报警
export function updateSos(data) {
  return request({
    url: '/system/sos',
    method: 'put',
    data: data,
  });
}

// 删除报警
export function delSos(id) {
  return request({
    url: '/system/sos/' + id,
    method: 'delete',
  });
}

// 查询求助人员列表
export function getSosUsers(query) {
  return request({
    url: '/system/user/listAssist',
    method: 'get',
    params: query,
  });
}

// 发起呼叫
export function goAssist(data) {
  return request({
    url: '/system/user/goAssist',
    method: 'post',
    data: data,
  });
}

// 分页查询报警记录
export function listAlarmPage(query) {
  return request({
    url: '/hat/alarm/page',
    method: 'get',
    params: query,
  });
}

// 查询报警详情
export function getAlarmDetail(id) {
  return request({
    url: '/hat/alarm/' + id,
    method: 'get',
  });
}

// 标记为已处理
export function handleAlarm(data) {
  return request({
    url: '/hat/alarm/handle',
    method: 'put',
    data: data
  });
}

// 接听操作
export function answerAlarm(id) {
  return request({
    url: '/hat/alarm/answer/' + id,
    method: 'put'
  });
}
