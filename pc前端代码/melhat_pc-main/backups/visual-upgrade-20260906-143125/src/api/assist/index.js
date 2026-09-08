import request from '@/utils/request'

// 接受协助
export function receiveAssist(businessId, deviceId) {
  const data = {
    businessId,
    deviceId
  }
  return request({
    url: '/taskAssistRecord/receiveAssist',
    method: 'post',
    data: data
  })
}

// 拒绝协助
export function rejectAssist(businessId, deviceId) {
  const data = {
    businessId,
    deviceId
  }
  return request({
    url: '/taskAssistRecord/rejectAssist',
    method: 'post',
    data: data
  })
}

// 协助结束
export function endAssist(businessId, deviceId, importance) {
  const data = {
    businessId,
    deviceId,
    importance
  }
  return request({
    url: '/taskAssistRecord/endAssist',
    method: 'post',
    data: data
  })
}
