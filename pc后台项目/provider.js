import { createSeed, TOKEN_KEY } from './seed'
import { createAdminService } from './service'

const REMOTE_QUERIES = new Set(['overview', 'details', 'devices', 'device', 'deviceOptions', 'deviceHistory', 'deviceChanges', 'master', 'person', 'record', 'options', 'impacts', 'assignments', 'assignmentHistory', 'assignmentCandidates', 'repairAssignees', 'maintenanceSummary', 'maintenanceOrders', 'maintenanceOrder', 'maintenanceRecords', 'deviceLifecycleHistory', 'audit', 'auditDetail', 'auditExport', 'authorizationPreview', 'context'])
const REMOTE_COMMANDS = new Set(['devices.create', 'devices.update', 'devices.configure', 'assignments.issue', 'assignments.return', 'maintenance.create', 'maintenance.assign', 'maintenance.start', 'maintenance.inspect', 'devices.disable', 'devices.restore', 'devices.scrap', 'maintenance.scrap'])
const REMOTE_MASTER = /^(people|organizations|areas|sites|dutyShifts)\.(create|update|status|delete)$/
const REMOTE_ACCESS = /^(accounts|roles)\.(create|update|status|delete)$|^accounts\.resetCredential$/
const REMOTE_ENTITIES = new Set(['people', 'organizations', 'areas', 'sites', 'dutyShifts', 'accounts', 'roles'])

let provider

function request(method, url, body) {
  const xhr = new XMLHttpRequest()
  xhr.open(method, url, false)
  xhr.setRequestHeader('Content-Type', 'application/json; charset=utf-8')
  try { xhr.send(body == null ? null : JSON.stringify(body)) }
  catch { throw Error('后端未连接，修改未保存') }
  if (xhr.status === 0) throw Error('后端未连接，修改未保存')
  let payload = {}
  try { payload = JSON.parse(xhr.responseText || '{}') } catch { payload = {} }
  if (xhr.status >= 400) {
    const error = Error(payload.message || '保存失败')
    error.code = payload.code || xhr.status
    error.errorCode = payload.errorCode
    throw error
  }
  return payload
}

function remoteKind(kind, input) {
  if (!REMOTE_QUERIES.has(kind)) return false
  if (kind === 'master' || kind === 'record' || kind === 'impacts') return REMOTE_ENTITIES.has(input?.entity)
  return true
}

export function getAdminProvider() {
  if (!provider) {
    let remote = null
    try { remote = request('GET', '/api/admin/v1/state').state || null } catch { remote = null }
    const initial = remote || createSeed()
    provider = createAdminService({ storage: window.sessionStorage, initialState: initial })
    if (!remote) {
      try { request('PUT', '/api/admin/v1/state', provider.exportState()) } catch { /* 后端未启动时先打开页面，不把整页停在空白。 */ }
    }
    provider.setRemoteSave(state => request('PUT', '/api/admin/v1/state', state))
    provider.setRemoteLogin((username, password) => request('POST', '/api/admin/v1/login', { username, password }))
    const localQuery = provider.query.bind(provider)
    const localExecute = provider.execute.bind(provider)
    provider.execute = (type, input = {}, options) => {
      if (options?.signal?.aborted) return Promise.reject(new DOMException('请求已取消', 'AbortError'))
      if (!REMOTE_COMMANDS.has(type) && !REMOTE_MASTER.test(type) && !REMOTE_ACCESS.test(type)) return localExecute(type, input, options)
      const accountId = window.sessionStorage.getItem(TOKEN_KEY)
      const result = request('POST', '/api/admin/v1/execute', { type, accountId, input })
      const saved = request('GET', '/api/admin/v1/state')
      if (saved.state) provider.replaceState(saved.state)
      return Promise.resolve(result)
    }
    provider.query = (kind, input = {}, options) => {
      if (options?.signal?.aborted) return Promise.reject(new DOMException('请求已取消', 'AbortError'))
      if (!remoteKind(kind, input)) return localQuery(kind, input, options)
      const accountId = window.sessionStorage.getItem(TOKEN_KEY)
      return Promise.resolve(request('POST', '/api/admin/v1/query', { kind, accountId, input }))
    }
  }
  return provider
}
