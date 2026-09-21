import test from 'node:test'
import assert from 'node:assert/strict'
import { createSeed } from '../src/mock/seed.js'
import { queryDataset } from '../src/mock/engine.js'
import { createMemoryRepository } from '../src/mock/storage.js'
import { portalMenus, portalPages, menuOwner } from '../src/router/menus.js'
import { workspaceTarget } from '../src/utils/workspace-navigation.js'
import { safeWorkspaceReturn } from '../src/utils/spatial-contract.js'
const base = '/api/portal/v1', siteId = 'mock-site-1'
const read = (data, role = 'owner', site = siteId) => queryDataset(data, role, base + '/workbench', { siteId: site })
test('seven work entrances retain all nine original page registrations', () => {
  assert.equal(portalMenus.length, 7); assert.equal(portalPages.length, 10)
  for (const path of ['/video', '/video/device-1', '/location']) assert.equal(menuOwner(path), '/location')
  assert.equal(menuOwner('/statistics'), '/materials'); assert.equal(menuOwner('/personnel/9007199254740993101'), '/personnel')
  assert.equal(menuOwner('/alarms/event-1/verification'), '/alarms')
})
test('workbench metrics and complete drilldown share facts, not page totals', () => {
  const data = createSeed(), w = read(data)
  assert.equal(w.duty.data.length, 25); assert.equal(w.equipment.data.length, 68)
  assert.equal(w.open.data.length, 19); assert.equal(w.unknown.data.length, 0)
  assert.ok(w.mine.data.length > 0)
  assert.ok(w.mine.data.every(e => e.handlingStatus === 'UNHANDLED' && w.open.data.includes(e)))
  assert.equal(new Set(w.equipment.data.map(d => d.deviceId)).size, w.equipment.data.length)
  assert.ok(w.duty.data.every(p => typeof p.personId === 'string'))
})
test('identity, site and data availability are independent', () => {
  const data = createSeed()
  assert.equal(read(data, 'reader').mine.state, 'FORBIDDEN')
  assert.ok(read(data, 'verifier').mine.data.every(e => e.handlingStatus === 'UNHANDLED'))
  assert.equal(read(data, 'owner', 'mock-site-empty').duty.data.length, 0)
  assert.throws(() => read(data, 'verifier', 'mock-site-2'), e => e.code === 403)
  assert.throws(() => read(data, ''), e => e.code === 401)
  for (const [mode, state] of [['failure', 'ERROR'], ['not-integrated', 'NOT_INTEGRATED'], ['forbidden', 'FORBIDDEN']]) {
    data.config = { module: 'events', mode }; const w = read(data)
    assert.equal(w.open.state, state); assert.equal(w.open.data, null); assert.equal(w.duty.data.length, 25)
  }
})
test('revision commits only successful updates, read never mutates, reset restores seeds', () => {
  const repo = createMemoryRepository(), before = repo.readDataset()
  repo.transact(d => { d.entities.events[1].handlingStatus = 'HANDLED' })
  assert.equal(repo.readDataset().meta.businessRevision, 1)
  assert.throws(() => repo.transact(d => { d.entities.people = []; throw new Error('failed') }))
  assert.equal(repo.readDataset().entities.people.length, 50)
  assert.equal(repo.resetDataset().entities.events[1].handlingStatus, before.entities.events[1].handlingStatus)
})
test('same-site monitor selection only and safe workbench return', () => {
  const selection = { siteId, deviceId: 'device-1-1-helmet' }
  assert.equal(workspaceTarget({ path: '/video' }, siteId, selection).query.selectedId, selection.deviceId)
  assert.equal(workspaceTarget({ path: '/video' }, 'mock-site-2', selection).query.selectedId, undefined)
  assert.equal(workspaceTarget({ path: '/location', query: { tab: 'tracks' } }, siteId, selection).query.deviceId, selection.deviceId)
  assert.equal(safeWorkspaceReturn('/overview?siteId=mock-site-1&evil=x'), '/overview?siteId=mock-site-1')
  assert.equal(safeWorkspaceReturn('//evil.test/overview'), '/personnel')
})
