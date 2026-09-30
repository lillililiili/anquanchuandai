import { createSeed, TOKEN_KEY, SESSION_VERSION_KEY } from './seed'
import { createAdminService } from './service'

const REMOTE_QUERIES = new Set(['overview', 'details', 'devices', 'device', 'deviceOptions', 'deviceHistory', 'deviceChanges', 'master', 'person', 'record', 'options', 'impacts', 'assignments', 'assignmentHistory', 'assignmentCandidates', 'audit', 'auditDetail', 'auditExport', 'authorizationPreview', 'context'])
const REMOTE_COMMANDS = new Set(['devices.create', 'devices.update', 'devices.configure', 'assignments.issue', 'assignments.return'])
const REMOTE_MASTER = /^(people|organizations|areas|sites|dutyShifts)\.(create|update|status|delete)$/
const REMOTE_ACCESS = /^(accounts|roles)\.(create|update|status|delete)$|^accounts\.resetCredential$/
const REMOTE_ENTITIES = new Set(['people', 'organizations', 'areas', 'sites', 'dutyShifts', 'accounts', 'roles'])

let provider
const AUTH_KEY = 'wearable-admin-token'

function request(method, url, body) {
  const xhr = new XMLHttpRequest()
  xhr.open(method, url, false)
  xhr.setRequestHeader('Content-Type', 'application/json; charset=utf-8')
  xhr.setRequestHeader('X-Wearable-Token', window.sessionStorage.getItem(AUTH_KEY) || '')
  try { xhr.send(body == null ? null : JSON.stringify(body)) }
  catch { throw Error('后端未连接，修改未保存') }
  if (xhr.status === 0) throw Error('后端未连接，修改未保存')
  let payload = {}
  try { payload = JSON.parse(xhr.responseText || '{}') } catch { payload = {} }
  if (xhr.status >= 400) {
    if (xhr.status === 401) {
      window.sessionStorage.removeItem(AUTH_KEY)
      window.sessionStorage.removeItem(TOKEN_KEY)
      window.sessionStorage.removeItem(SESSION_VERSION_KEY)
      provider?.invalidate()
    }
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
    if (window.sessionStorage.getItem(AUTH_KEY)) {
      try { remote = request('GET', '/api/admin/v1/state').state || null } catch { remote = null }
    } else {
      window.sessionStorage.removeItem(TOKEN_KEY)
      window.sessionStorage.removeItem(SESSION_VERSION_KEY)
    }
    const initial = remote || createSeed()
    provider = createAdminService({ storage: window.sessionStorage, initialState: initial })
    provider.setRemoteSave(() => { throw Error('此操作尚未开放业务接口，修改未保存') })
    provider.setRemoteLogin((username, password) => {
      const result = request('POST', '/api/admin/v1/login', { username, password })
      if (!result.token) throw Error('登录响应缺少会话凭据')
      window.sessionStorage.setItem(AUTH_KEY, result.token)
      provider.replaceState(request('GET', '/api/admin/v1/state').state)
      return result
    })
    const localLogout = provider.logout.bind(provider)
    provider.logout = () => {
      try { request('POST', '/api/admin/v1/logout') }
      finally { window.sessionStorage.removeItem(AUTH_KEY); localLogout() }
    }
    const localQuery = provider.query.bind(provider)
    provider.execute = (type, input = {}, options) => {
      if (options?.signal?.aborted) return Promise.reject(new DOMException('请求已取消', 'AbortError'))
      if (!REMOTE_COMMANDS.has(type) && !REMOTE_MASTER.test(type) && !REMOTE_ACCESS.test(type)) throw Error('此操作尚未开放业务接口，修改未保存')
      const accountId = window.sessionStorage.getItem(TOKEN_KEY)
      const result = request('POST', '/api/admin/v1/execute', { type, accountId, input })
      const saved = request('GET', '/api/admin/v1/state')
      if (saved.state) provider.replaceState(saved.state)
      return Promise.resolve(result)
    }
    provider.query = (kind, input = {}, options) => {
      if (options?.signal?.aborted) return Promise.reject(new DOMException('请求已取消', 'AbortError'))
      if (['repairAssignees', 'deviceLifecycleHistory'].includes(kind) || kind.startsWith('maintenance')) throw Error('维修与退役功能已移除')
      if (!remoteKind(kind, input)) return localQuery(kind, input, options)
      const accountId = window.sessionStorage.getItem(TOKEN_KEY)
      return Promise.resolve(request('POST', '/api/admin/v1/query', { kind, accountId, input }))
    }
  }
  return provider
}
