import request from '@/utils/request';

// 查询巡检检查项配置列表
export function listConfig(query) {
  return request({
    url: '/system/items/config/list',
    method: 'get',
    params: query,
  });
}

// 查询巡检检查项配置详细
export function getConfig(id) {
  return request({
    url: '/system/items/config/' + id,
    method: 'get',
  });
}

// 新增巡检检查项配置
export function addConfig(data) {
  return request({
    url: '/system/items/config',
    method: 'post',
    data: data,
  });
}

// 修改巡检检查项配置
export function updateConfig(data) {
  return request({
    url: '/system/items/config',
    method: 'put',
    data: data,
  });
}

// 删除巡检检查项配置
export function delConfig(id) {
  return request({
    url: '/system/items/config/' + id,
    method: 'delete',
  });
}

//批量保存数据
export function addConfigBath(data) {
  return request({
    url: '/system/items/config/addBatch',
    method: 'post',
    data: data,
  });
}
