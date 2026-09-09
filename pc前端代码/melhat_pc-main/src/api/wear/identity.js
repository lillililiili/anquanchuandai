import request from '@/utils/request'

export function getMe() {
  return request({
    url: '/api/v1/me',
    method: 'get'
  })
}

export function listAuthorizedSites() {
  return request({
    url: '/api/v1/sites',
    method: 'get'
  })
}

export function selectCurrentSite(siteId) {
  return request({
    url: '/api/v1/me/current-site',
    method: 'put',
    data: { siteId }
  })
}
