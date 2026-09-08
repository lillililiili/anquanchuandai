import request from '@/utils/request'

// 分页查询广播记录
export function listTtsRecord(query) {
  return request({
    url: '/hat/tts/broadcast/page',
    method: 'get',
    params: query
  })
}

// 创建单播
export function addUnicast(data) {
  return request({
    url: '/hat/tts/broadcast/single-broadcast',
    method: 'post',
    data: data
  })
}

// 创建组播
export function addMulticast(data) {
  return request({
    url: '/hat/tts/broadcast/team-broadcast',
    method: 'post',
    data: data
  })
}

// 创建群播
export function addGroupcast(data) {
  return request({
    url: '/hat/tts/broadcast/group-broadcast',
    method: 'post',
    data: data
  })
}
