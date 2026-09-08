import request from '@/utils/request'

// 对讲记录列表（分页）
export function listIntercomRecord(query) {
  return request({
    url: '/hat/intercom/record/page',
    method: 'get',
    params: query
  })
}

// 根据ID获取对讲记录详情
export function getIntercomRecord(id) {
  return request({
    url: '/hat/intercom/record/' + id,
    method: 'get'
  })
}

// 创建单呼
export function createSingleCall(data) {
  return request({
    url: '/hat/intercom/record/single-call',
    method: 'post',
    data: data
  })
}

// 创建群呼
export function createGroupCall(data) {
  return request({
    url: '/hat/intercom/record/group-call',
    method: 'post',
    data: data
  })
}

// 创建组呼
export function createTeamCall(data) {
  return request({
    url: '/hat/intercom/record/team-call',
    method: 'post',
    data: data
  })
}

// 结束对讲
export function endIntercom(data) {
  return request({
    url: '/hat/intercom/record/agoraEnd',
    method: 'put',
    data: data
  })
}