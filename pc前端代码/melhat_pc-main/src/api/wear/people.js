import request from '@/utils/request'

export function listPeople(params) {
  return request({ url: '/api/v1/people', method: 'get', params })
}

export function peopleOptions(params) {
  return request({ url: '/api/v1/people/options', method: 'get', params })
}

export function getPerson(id) {
  return request({ url: '/api/v1/people/' + id, method: 'get' })
}

export function createPerson(data) {
  return request({ url: '/api/v1/people', method: 'post', data })
}

export function updatePerson(id, data) {
  return request({ url: '/api/v1/people/' + id, method: 'put', data })
}

export function changePersonStatus(id, data) {
  return request({ url: '/api/v1/people/' + id + '/status', method: 'put', data })
}

export function listTeams() {
  return request({ url: '/api/v1/teams', method: 'get' })
}

export function createTeam(data) {
  return request({ url: '/api/v1/teams', method: 'post', data })
}

export function updateTeam(id, data) {
  return request({ url: '/api/v1/teams/' + id, method: 'put', data })
}

export function listContractors() {
  return request({ url: '/api/v1/contractors', method: 'get' })
}

export function createContractor(data) {
  return request({ url: '/api/v1/contractors', method: 'post', data })
}

export function updateContractor(id, data) {
  return request({ url: '/api/v1/contractors/' + id, method: 'put', data })
}

export function listSpaces(params) {
  return request({ url: '/api/v1/spaces', method: 'get', params })
}

export function createSpace(data) {
  return request({ url: '/api/v1/spaces', method: 'post', data })
}

export function updateSpace(id, data) {
  return request({ url: '/api/v1/spaces/' + id, method: 'put', data })
}
