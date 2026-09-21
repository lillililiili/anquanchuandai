import { identities } from './seed.js'
import { failure } from './errors.js'
import { normalizeRing } from '../utils/fence-geometry.js'
import { MAX_BLOB_BYTES } from './local-file.js'
import { videoAccess } from './video-service.js'
const clone = v => structuredClone(v)
function scope(dataset, role, siteId, write = false) {
  const identity = identities.find(i => i.id === role)
  if (!identity) throw failure(401, '本地会话失效')
  if (!identity.sites.includes(siteId)) throw failure(403, '无权访问该厂站')
  if (write && role !== 'owner') throw failure(403, '仅负责人可修改围栏或资料')
}
function find(dataset, kind, id, siteId) {
  const row = dataset.entities[kind].find(i => i.id === id && i.siteId === siteId)
  if (!row) throw failure(404, '对象不存在或不可见')
  return row
}
export function spatialRead(dataset, role, action, q) {
  scope(dataset, role, q.siteId)
  const module = action === 'versions' ? 'fences' : 'materials'
  if (dataset.config.module === module && dataset.config.mode !== 'normal') throw failure(dataset.config.mode === 'forbidden' ? 403 : 503, '当前预置数据不可访问，未返回缓存数据')
  if (action === 'options') return { people: dataset.entities.people.filter(i => i.siteId === q.siteId).map(i => ({ id: i.personId, name: i.name })), works: dataset.entities.works.filter(i => i.siteId === q.siteId).map(i => ({ id: i.workId, name: i.name })), events: dataset.entities.events.filter(i => i.siteId === q.siteId).map(i => ({ id: i.eventId, name: i.title })) }
  if (action === 'versions') {
    const versions = (dataset.relations.fenceVersions || []).filter(i => i.id === q.id && i.siteId === q.siteId)
    if (versions.length) return clone(versions)
    return [{ ...clone(find(dataset, 'fences', q.id, q.siteId)), action: 'SEED', recordedAt: null }]
  }
  const material = find(dataset, 'materials', q.id, q.siteId)
  if (action === 'blob') {
    const blob = dataset.entities.materialBlobs?.[material.id]
    if (!blob) throw failure(404, '仅有元数据，浏览器内存中没有文件')
    return { blob, name: material.name, type: material.type, version: material.version }
  }
  throw failure(404, '未实现的本地查询')
}
export function spatialCommand(dataset, role, action, input, validatedFile) {
  scope(dataset, role, input.siteId, true)
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(input.operationId || '')) throw failure(400, '操作标识无效')
  const module = action.startsWith('fence') ? 'fences' : 'materials'
  if (dataset.config.module === module && dataset.config.mode !== 'normal') throw failure(dataset.config.mode === 'forbidden' ? 403 : 503, '当前场景不允许修改，数据未保存')
  dataset.relations.spatialOperations ||= []
  const fingerprint = JSON.stringify({ action, ...input, file: undefined })
  const previous = dataset.relations.spatialOperations.find(i => i.id === input.operationId)
  if (previous) {
    if (previous.fingerprint !== fingerprint || previous.role !== role) throw failure(409, '操作标识已用于其他输入')
    return { ...clone(previous.result), replayed: true }
  }
  const now = new Date().toISOString(), e = dataset.entities
  let result
  const versionCheck = item => { if (input.expectedVersion !== item.version) throw failure(409, '版本已变化，请重新读取后操作') }
  if (module === 'fences') {
    const old = input.id ? find(dataset, 'fences', input.id, input.siteId) : null
    if (old) versionCheck(old)
    if (!old && action !== 'fence-save') throw failure(404, '围栏不存在')
    dataset.relations.fenceVersions ||= []
    if (old && !dataset.relations.fenceVersions.some(v => v.id === old.id)) dataset.relations.fenceVersions.push({ ...clone(old), action: 'SEED', recordedAt: null })
    let next = { ...clone(old), id: old?.id || 'mock-fence-' + input.operationId, siteId: input.siteId, version: (old?.version || 0) + 1, sourceTime: now, effectiveAt: null, source: 'MOCK_MANUAL' }
    if (action === 'fence-save') {
      if (!input.name?.trim() || input.name.length > 100 || !['ALL', 'HELMET', 'BELT', 'WATCH'].includes(input.appliesTo)) throw failure(400, '请填写名称及设备类型')
      const ruleType = input.ruleType ?? old?.ruleType ?? null
      if (ruleType !== null && !['DENY_ENTRY', 'DENY_EXIT'].includes(ruleType)) throw failure(400, '无效的告警条件')
      const teamId = input.teamId ?? old?.teamId ?? null
      const team = e.teams.find(t => t.teamId === teamId && t.siteId === input.siteId)
      if (teamId !== null && teamId !== 'ALL' && !team) throw failure(400, '班组不存在或不属于当前厂站')
      next.teamId = teamId
      next.teamName = team?.name || null
      try { next.ring = normalizeRing(input.ring) } catch (err) { throw failure(400, err.message) }
      next = { ...next, name: input.name.trim(), coordinateSystem: 'WGS84', ruleType, appliesTo: input.appliesTo, rule: ruleType ? (ruleType === 'DENY_ENTRY' ? '禁入' : '禁出') + ' · ' + input.appliesTo + '（人工本地规则，非真实违规判断）' : null, status: old?.status || 'DISABLED' }
    } else if (action === 'fence-toggle') next.status = old.status === 'ENABLED' ? 'DISABLED' : 'ENABLED'
    else if (action !== 'fence-delete') throw failure(400, '未知围栏操作')
    e.fences = e.fences.filter(i => i.id !== next.id)
    if (action !== 'fence-delete') e.fences.unshift(next)
    dataset.relations.fenceVersions.push({ ...clone(next), action, recordedAt: now, actor: role })
    result = { id: next.id, version: next.version, changedEntities: ['fences'] }
  } else if (action === 'material-import') {
    if (!validatedFile || !(input.file instanceof Blob)) throw failure(400, '文件尚未通过校验')
    let generatedDevice = null
    if (input.generationMethod) {
      const key = { MOCK_CAPTURE: 'capture', MOCK_RECORD: 'record' }[input.generationMethod]
      if (!key || validatedFile.type !== (key === 'capture' ? 'PHOTO' : 'VIDEO')) throw failure(400, '生成方式与资料类型不一致')
      generatedDevice = videoAccess(dataset, role, input.siteId, input.deviceId, key)
      if (input.capturedAt) throw failure(400, '本地视频没有真实设备拍摄时间')
    }
    e.materialBlobs ||= {}
    const used = Object.values(e.materialBlobs).reduce((sum, b) => sum + b.size, 0)
    if (used + input.file.size > MAX_BLOB_BYTES) throw failure(413, '内存素材超过200MB，请移除未引用资料或重置；不会自动淘汰证据')
    if (input.capturedAt && (!/^\d{4}-\d\d-\d\dT.*Z$/.test(input.capturedAt) || !Number.isFinite(Date.parse(input.capturedAt)))) throw failure(400, '采集时间必须为UTC或未知')
    const id = 'mock-material-' + input.operationId
    e.materialBlobs[id] = input.file
    e.materials.unshift({ id, siteId: input.siteId, name: validatedFile.name, type: validatedFile.type, mime: validatedFile.mime, size: validatedFile.size, version: 1, digest: input.digest, source: 'BROWSER_MEMORY', accessibility: 'MEMORY_FILE', capturedAt: input.capturedAt || null, receivedAt: now, importedAt: now, attribution: 'UNKNOWN', workAttribution: 'UNKNOWN', eventAttribution: 'UNKNOWN', deviceId: null, personId: null, workId: null, eventId: null })
    if (generatedDevice) Object.assign(e.materials[0], { deviceId: generatedDevice.deviceId, deviceCode: generatedDevice.deviceCode, generationMethod: input.generationMethod, generatedAt: input.generatedAt || now, capturedAt: null })
    result = { id, version: 1, changedEntities: ['materials'] }
  } else {
    const item = find(dataset, 'materials', input.id, input.siteId); versionCheck(item)
    const refs = (dataset.relations.materialReferences || []).filter(r => r.materialId === item.id && r.version === item.version)
    if (action === 'material-reference') {
      if (!input.eventId || !e.events.some(i => i.siteId === input.siteId && i.eventId === input.eventId)) throw failure(404, '引用事件不存在或不可见')
      dataset.relations.materialReferences ||= []
      if (!refs.some(r => r.eventId === input.eventId)) dataset.relations.materialReferences.push({ materialId: item.id, siteId: item.siteId, eventId: input.eventId, version: item.version, digest: item.digest || null, name: item.name, type: item.type, capturedAt: item.capturedAt, receivedAt: item.receivedAt, source: 'MANUAL_MOCK', recordedAt: now })
      item.frozen = true
    } else {
      if (refs.length || item.frozen) throw failure(409, '该资料版本已冻结引用，不能覆盖或删除')
      if (action === 'material-delete') { e.materials = e.materials.filter(i => i.id !== item.id); if (e.materialBlobs) delete e.materialBlobs[item.id] }
      else if (action === 'material-associate') {
        for (const [key, collection, idKey, nameKey] of [['personId', 'people', 'personId', 'personName'], ['workId', 'works', 'workId', 'workName'], ['eventId', 'events', 'eventId', 'eventName']]) {
          const object = input[key] ? e[collection].find(i => i.siteId === input.siteId && i[idKey] === input[key]) : null
          if (input[key] && !object) throw failure(404, '关联对象不存在或不可见')
          item[key] = object?.[idKey] || null; item[nameKey] = object?.name || object?.title || null
        }
        item.attribution = item.workAttribution = item.eventAttribution = 'MANUAL_MOCK'; item.associationSource = 'MANUAL_MOCK'; item.version++
      } else throw failure(400, '未知资料操作')
    }
    result = { id: item.id, version: item.version, changedEntities: ['materials'] }
  }
  dataset.relations.spatialOperations.push({ id: input.operationId, role, fingerprint, result: clone(result), recordedAt: now })
  return result
}
