import request from '@/utils/request'

// 人员定位
export function personLocation(id) {
  return request({
    url: '/aip/head/band/my/location/'+id,
    method: 'get',
  })
}

// 人员轨迹
export function personTrack(query) {
  return request({
    url: '/aip/head/band/location/record',
    method: 'get',
    params: query
  })
}

// 轨迹回放查询
export function trackPlaybackQuery(data) {
  return request({
    url: '/hat/location/record/query',
    method: 'post',
    data: data
  })
}

// 获取轨迹关联的文件
export function getRelatedFiles(query) {
  return request({
    url: '/hat/location/record/relatedFiles',
    method: 'get',
    params: query
  })
}