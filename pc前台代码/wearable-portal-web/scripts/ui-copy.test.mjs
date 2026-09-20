import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import { createSeed, identities } from '../src/mock/seed.js'

test('visible Chinese copy no longer uses demonstration terminology', () => {
  function inspect(dir) {
    for (const item of fs.readdirSync(dir, { withFileTypes: true })) {
      const path = `${dir}/${item.name}`
      if (item.isDirectory()) inspect(path)
      else if (/\.(vue|js)$/.test(path)) assert.doesNotMatch(fs.readFileSync(path, 'utf8'), /演示|模拟/, path)
    }
  }
  inspect('src')
})
test('login uses the standard account form without identity or reset controls', () => {
  const login = fs.readFileSync('src/views/login/LoginView.vue', 'utf8')
  assert.match(login, /工作账号登录/)
  assert.match(login, /autocomplete="current-password"/)
  assert.doesNotMatch(login, /工作身份|重置本地数据|本地工作空间|MockLogin/)
  const layout = fs.readFileSync('src/layouts/PortalLayout.vue', 'utf8')
  assert.doesNotMatch(layout, /<MockControls/)
  assert.match(layout, /服务未接入/)
})
test('public names and business codes use neutral labels, without changing protocol identities', () => {
  const seed = createSeed()
  assert.deepEqual(identities.map(i => i.name), ['负责人', '核验员', '只读查看员'])
  assert.equal(seed.entities.sites[0].siteId, 'mock-site-1')
  for (const items of Object.values(seed.entities)) for (const item of items) {
    for (const key of ['name', 'title', 'deviceCode', 'personCode', 'sourceWorkNo', 'sourceEventId', 'digest']) {
      if (item[key]) assert.doesNotMatch(item[key], /演示|模拟|mock|demo/i)
    }
  }
})
