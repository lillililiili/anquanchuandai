import request from '@/utils/request'

// 查询安全帽列表
export function listHat(query) {
  return request({
    url: '/system/hat/list',
    method: 'get',
    params: query
  })
}

// 查询安全帽详细
export function getHat(id) {
  return request({
    url: '/system/hat/' + id,
    method: 'get'
  })
}

// 新增安全帽
export function addHat(data) {
  return request({
    url: '/system/hat',
    method: 'post',
    data: data
  })
}

// 修改安全帽
export function updateHat(data) {
  return request({
    url: '/system/hat/edit',
    method: 'put',
    data: data
  })
}

// 删除安全帽
export function delHat(id) {
  return request({
    url: '/system/hat/' + id,
    method: 'delete'
  })
}

// 删除安全帽
export function getDetail(id) {
  return request({
    url: '/system/hat/getDetail/' + id,
    method: 'get'
  })
}

// 查询安全帽图片
export function getHatImgs(query) {
  return request({
    url: '/hatImage/getImagesList/' + query.deviceNumber,
    method: 'get',
    params: { pageNum: query.pageNum, pageSize: query.pageSize }
  })
}

// 查询在线人员位置
export function getUserOnlineHatAddress() {
  return request({
    url: '/system/hat/getUserOnlineHatAddress',
    method: 'get'
  })
}

//查询某个人员位置
export function getUserRealTimeLocation(id) {
  return request({
    url: '/system/hat/getUserRealTimeLocation/' + id,
    method: 'get'
  })
}
