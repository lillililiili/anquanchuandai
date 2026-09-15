import request from '@/utils/request'
import { saveAs } from 'file-saver'

export function getAdminOverview() {
  return request({ url: '/api/v1/admin/overview', method: 'get' })
}

export function exportResource(resource, params) {
  return request({
    url: `/api/v1/${resource}/export`,
    method: 'post',
    data: params,
    responseType: 'blob'
  })
}

export function downloadExport(resource, params, filename) {
  return exportResource(resource, params).then(data => {
    saveAs(new Blob([data]), filename)
  })
}

export function downloadImportTemplate(resource, filename) {
  return request({
    url: `/api/v1/${resource}/import-template`,
    method: 'get',
    responseType: 'blob'
  }).then(data => saveAs(new Blob([data]), filename))
}

export function importResource(resource, file, updateExisting = false) {
  const data = new FormData()
  data.append('file', file)
  data.append('updateExisting', String(updateExisting))
  return request({
    url: `/api/v1/${resource}/import`,
    method: 'post',
    data,
    headers: { 'Content-Type': 'multipart/form-data', repeatSubmit: false },
    timeout: 120000
  })
}
