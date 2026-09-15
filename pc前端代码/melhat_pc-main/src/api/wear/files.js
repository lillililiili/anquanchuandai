import request from '@/utils/request'

export function listFiles(params) { return request({ url: '/api/v1/files', method: 'get', params }) }
export function getFileRecord(id) { return request({ url: '/api/v1/files/' + id, method: 'get' }) }
export function downloadFileRecord(id) { return request({ url: `/api/v1/files/${id}/download`, method: 'get', responseType: 'blob' }) }
