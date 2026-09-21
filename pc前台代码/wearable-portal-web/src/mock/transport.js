import { queryDataset, failure, moduleOf } from './engine.js'
import { identities, permissionsFor } from './seed.js'
import { authenticate } from './credentials.js'
import { assignmentCommand } from './equipment-service.js'
import { spatialCommand, spatialRead } from './spatial-service.js'
import { inspectFile, decodeFile } from './local-file.js'
import { videoAccess, privacyCommand } from './video-service.js'
import { queryWorks, workEditor, workCommand } from './work-service.js'
import { eventCommand } from './event-service.js'
import { queryDispatch, dispatchCommand } from './dispatch-service.js'
export const MOCK_TOKEN_KEY = 'Wearable-Portal-Mock-Token'
export function delay(ms, signal) {
  return new Promise((resolve, reject) => {
    const cancel = () => { clearTimeout(timer); signal?.removeEventListener('abort', cancel); reject(failure('ERR_CANCELED', '请求已取消')) }
    const timer = setTimeout(() => { signal?.removeEventListener('abort', cancel); resolve() }, ms)
    if (signal?.aborted) cancel(); else signal?.addEventListener('abort', cancel, { once: true })
  })
}
export function createTransport({ read, update, session, wait = delay }) {
  let unauthorized = () => {}, count = 0, generation = 0
  const roleFor = token => { try { const s = JSON.parse(token); return s?.kind === 'MOCK_ONLY' && identities.some(i => i.id === s.role) ? s.role : null } catch { return null } }
  async function run(method, path, body, config = {}) {
    const requestId = `mock-${++count}`, token = config.skipAuth ? '' : session.getItem(MOCK_TOKEN_KEY), current = generation
    try {
      let dataset = await read()
      let ms = 200
      if (method === 'GET' && (path.startsWith('/api/portal/') || path.startsWith('/mock-works/') || path.startsWith('/mock-dispatch/')) && moduleOf(path) === dataset.config.module && dataset.config.slowNext) {
        await update(d => { if (d.config.slowNext) { ms = 3000; d.config.slowNext = false } })
      }
      await wait(ms, config.signal)
      if (config.signal?.aborted || current !== generation || !config.skipAuth && session.getItem(MOCK_TOKEN_KEY) !== token) throw failure('ERR_CANCELED', '会话已变化')
      dataset = await read()
      if (config.signal?.aborted || current !== generation || !config.skipAuth && session.getItem(MOCK_TOKEN_KEY) !== token) throw failure('ERR_CANCELED', '会话已变化')
      if (method === 'POST' && path === '/login') {
        const role = authenticate(body)
        generation++
        return { code: 200, token: JSON.stringify({ kind: 'MOCK_ONLY', role, nonce: requestId + '-' + Date.now() }), requestId }
      }
      if (method === 'GET' && path === '/captchaImage') return { code: 200, captchaEnabled: false, requestId }
      const role = roleFor(token)
      if (!role) throw failure(401, '登录已失效，请重新登录')
      if (method === 'GET' && path === '/getInfo') { const i = identities.find(i => i.id === role); return { code: 200, user: { userId: 'mock-' + role, userName: role, nickName: i.name }, roles: [role], permissions: permissionsFor(role), requestId } }
      if (method === 'POST' && path === '/logout') { generation++; return { code: 200, requestId } }
      if (method === 'GET' && path === '/mock-dispatch/query') return { code: 200, data: queryDispatch(dataset, role, config.params), requestId }
      if (method === 'POST' && path.startsWith('/mock-dispatch/')) {
        let result
        await update(draft => {
          if (config.signal?.aborted || current !== generation || session.getItem(MOCK_TOKEN_KEY) !== token) throw failure('ERR_CANCELED', '会话已变化，未保存')
          result = dispatchCommand(draft, role, path.slice('/mock-dispatch/'.length), body)
          if (result.replayed) return false
        })
        return { code: 200, data: result, requestId }
      }
      if (method === 'GET' && path === '/mock-works/query') return { code: 200, data: queryWorks(dataset, role, config.params), requestId }
      if (method === 'GET' && path === '/mock-works/editor') return { code: 200, data: workEditor(dataset, role, config.params), requestId }
      if (method === 'POST' && path.startsWith('/mock-works/')) {
        let result
        await update(draft => {
          if (config.signal?.aborted || current !== generation || session.getItem(MOCK_TOKEN_KEY) !== token) throw failure('ERR_CANCELED', '会话已变化，未保存')
          result = workCommand(draft, role, path.slice('/mock-works/'.length), body)
          if (result.replayed) return false
        })
        return { code: 200, data: result, requestId }
      }
      if (path.startsWith('/mock-events/') && method === 'POST') {
        let result
        await update(draft => {
          if (config.signal?.aborted || current !== generation || session.getItem(MOCK_TOKEN_KEY) !== token) throw failure('ERR_CANCELED', '会话已变化，未保存')
          result = eventCommand(draft, role, path.slice('/mock-events/'.length), body)
          if (result.replayed) return false
        })
        return { code: 200, data: result, requestId }
      }
      if (path === '/mock-video/access' && method === 'GET') return { code: 200, data: structuredClone(videoAccess(dataset, role, config.params.siteId, config.params.deviceId, config.params.key)), requestId }
      if (path === '/mock-video/privacy' && method === 'POST') {
        let result
        await update(draft => {
          if (config.signal?.aborted || current !== generation || session.getItem(MOCK_TOKEN_KEY) !== token) throw failure('ERR_CANCELED', '会话已变化')
          result = privacyCommand(draft, role, body)
        })
        return { code: 200, data: result, requestId }
      }
      if (path.startsWith('/mock-spatial/')) {
        const action = path.slice('/mock-spatial/'.length)
        if (method === 'GET') return { code: 200, data: spatialRead(dataset, role, action, config.params), requestId }
        let validatedFile, result
        if (action === 'material-import') {
          validatedFile = await inspectFile(body.file, body.name)
          await decodeFile(body.file, validatedFile.type, config.signal)
          const digest = await crypto.subtle.digest('SHA-256', await body.file.arrayBuffer())
          body = { ...body, digest: [...new Uint8Array(digest)].map(n => n.toString(16).padStart(2, '0')).join('') }
        }
        await update(draft => {
          if (config.signal?.aborted || generation !== current || session.getItem(MOCK_TOKEN_KEY) !== token) throw failure('ERR_CANCELED', '会话或查询已变化，未保存')
          result = spatialCommand(draft, role, action, body, validatedFile)
          if (result.replayed) return false
        })
        return { code: 200, data: result, requestId }
      }
      if (method === 'POST' && ['/api/portal/v1/equipment/issue', '/api/portal/v1/equipment/return'].includes(path)) {
        let result
        await update(draft => {
          if (config.signal?.aborted || generation !== current || session.getItem(MOCK_TOKEN_KEY) !== token) throw failure('ERR_CANCELED', '会话已变化，操作未提交')
          result = assignmentCommand(draft, role, path.split('/').at(-1), body)
          if (result.replayed) return false
        })
        return { code: 200, data: result, requestId }
      }
      if (method !== 'GET') throw failure(405, 'FE0 仅支持只读操作，未访问后端', 'MOCK_READ_ONLY')
      return { code: 200, data: structuredClone(queryDataset(dataset, role, path, config.params)), asOf: new Date().toISOString(), requestId }
    } catch (e) {
      e.requestId = requestId
      if (e.code === 401 && !config.skipUnauthorized) unauthorized(token)
      throw e
    }
  }
  return { get: (p, c) => run('GET', p, null, c), post: (p, b, c) => run('POST', p, b, c), setUnauthorizedHandler: fn => { unauthorized = fn }, expire: () => { generation++; unauthorized(session.getItem(MOCK_TOKEN_KEY)); session.removeItem(MOCK_TOKEN_KEY) } }
}
