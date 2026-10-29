import { createSeed, TOKEN_KEY, SESSION_VERSION_KEY } from './seed'
import { createAdminService } from './service'
import { projectSingleSimulatedWatch } from '../shared/simulated-watch.mjs'

const REMOTE_QUERIES = new Set(['devices', 'device', 'deviceOptions', 'deviceHistory', 'deviceChanges', 'deviceEvents', 'master', 'person', 'record', 'options', 'impacts', 'assignments', 'assignmentHistory', 'assignmentCandidates', 'audit', 'auditDetail', 'auditExport', 'authorizationPreview', 'context'])
const REMOTE_COMMANDS = new Set(['devices.create', 'devices.update', 'devices.configure', 'assignments.issue', 'assignments.return', 'people.dutyStatus'])
const REMOTE_MASTER = /^(people|sites|dutyShifts)\.(create|update|status|delete)$|^organizations\.(create|update|delete)$/
const REMOTE_ACCESS = /^(accounts|roles)\.(create|update|status|delete)$|^accounts\.resetCredential$/
const REMOTE_ENTITIES = new Set(['people', 'organizations', 'sites', 'dutyShifts', 'accounts', 'roles'])

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
  return responsePayload(xhr.status, payload)
}

function responsePayload(status, payload) {
  if (status >= 400) {
    if (status === 401) {
      window.sessionStorage.removeItem(AUTH_KEY)
      window.sessionStorage.removeItem(TOKEN_KEY)
      window.sessionStorage.removeItem(SESSION_VERSION_KEY)
      provider?.invalidate()
    }
    const error = Error(payload.message || '保存失败')
    error.code = payload.code || status
    error.errorCode = payload.errorCode
    error.fields = payload.fields || {}
    error.impacts = payload.impacts || []
    error.requestId = payload.requestId
    throw error
  }
  return payload
}

// Page reads must yield to rendering and allow navigation to cancel the request.
async function queryRequest(body, signal) {
  const token = window.sessionStorage.getItem(AUTH_KEY) || ''
  let response
  try {
    response = await fetch('/api/admin/v1/query', {
      method: 'POST', signal,
      headers: { 'Content-Type': 'application/json; charset=utf-8', 'X-Wearable-Token': token },
      body: JSON.stringify(body),
    })
  } catch (error) {
    if (error.name === 'AbortError') throw error
    throw Error('后端未连接，请稍后重试')
  }
  let payload = {}
  try { payload = await response.json() } catch (error) { if (error.name === 'AbortError') throw error }
  // A response from an earlier login must not clear or populate the new session.
  if (signal?.aborted || token !== (window.sessionStorage.getItem(AUTH_KEY) || '')) throw new DOMException('请求已取消', 'AbortError')
  return responsePayload(response.status, payload)
}

function remoteKind(kind, input) {
  if (!REMOTE_QUERIES.has(kind)) return false
  if (kind === 'master' || kind === 'record' || kind === 'impacts') return REMOTE_ENTITIES.has(input?.entity)
  return true
}

export function getAdminProvider() {
  if (!provider) {
    // Retire business-only browser state; authentication remains in sessionStorage.
    window.localStorage?.removeItem('wearable-admin-state-v1')
    let remote = null
    if (window.sessionStorage.getItem(AUTH_KEY)) {
      try { remote = request('GET', '/api/admin/v1/state').state || null } catch { remote = null }
    } else {
      window.sessionStorage.removeItem(TOKEN_KEY)
      window.sessionStorage.removeItem(SESSION_VERSION_KEY)
    }
    const initial = projectSingleSimulatedWatch(remote) || Object.fromEntries(Object.entries(createSeed()).map(([key, value]) => [key, Array.isArray(value) ? [] : value]))
    provider = createAdminService({ storage: window.sessionStorage, initialState: initial })
    const replaceState = provider.replaceState.bind(provider)
    provider.replaceState = next => replaceState(projectSingleSimulatedWatch(next))
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
      return queryRequest({ kind, accountId, input }, options?.signal)
    }
  }
  return provider
}
