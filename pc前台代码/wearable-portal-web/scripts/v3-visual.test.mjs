import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync, statSync } from 'node:fs'

const read = path => readFileSync(new URL('../' + path, import.meta.url), 'utf8')

test('V3 sample assets are local WebP files within the agreed lightweight budget', () => {
  let total = 0
  for (const name of ['login', 'equipment', 'human']) {
    const path = new URL('../src/assets/images/v3-' + name + '.webp', import.meta.url)
    const bytes = readFileSync(path)
    assert.equal(bytes.subarray(0, 4).toString(), 'RIFF')
    assert.equal(bytes.subarray(8, 12).toString(), 'WEBP')
    total += statSync(path).size
  }
  assert.ok(total < 300 * 1024)
})

test('V3 samples retain auth branches, vital provenance and authoritative metric sources', () => {
  const login = read('src/views/login/LoginView.vue')
  assert.doesNotMatch(login, /MockLogin/)
  assert.match(login, /onMounted\(refreshCaptcha\)/)
  assert.match(login, /await user.signIn/)
  const overview = read('src/views/overview/OverviewView.vue')
  assert.match(overview, /getWorkbench\(siteId.value, signal\)/)
  assert.match(overview, /section\(key\).data.length/)
  assert.match(overview, /AI 场景示意 · 非实时画面/)
  assert.match(read('src/components/equipment/DeviceProfile.vue'), /概念装备展示 · 非厂家实物/)
  const vitals = read('src/components/personnel/VitalSignsPanel.vue')
  assert.match(vitals, /vitalValue\(card.reading\)/)
  assert.match(vitals, /预置体征，非实时测量；手表能力待确认/)
  assert.match(vitals, /v-if="showcase"/)
  assert.match(vitals, /<svg v-else/)
})

test('V3 sample styles use local assets and preserve reduced-motion protection', () => {
  const style = read('src/styles/v3-samples.scss')
  assert.doesNotMatch(style, /https?:\/\//)
  assert.match(style, /max-width: 1050px/)
  assert.match(style, /max-height: 85dvh/)
  assert.match(read('src/styles/index.scss'), /prefers-reduced-motion: reduce/)
})

test('V3 rollout covers workspaces without external assets or viewport overrides', () => {
  const style = read('src/styles/v3-workspaces.scss')
  for (const selector of ['personnel-table-panel', 'equipment-panel', 's2-map', 'video-slot', 'work-panel', 'event-section', 'dispatch-panel', 'stats-metric', 'el-dialog', 'error-page']) assert.ok(style.includes(selector), selector)
  assert.doesNotMatch(style, /https?:\/\//)
  assert.doesNotMatch(style, /zoom\s*:|transform:\s*scale/)
  assert.match(style, /prefers-reduced-motion:reduce/)
  const main = read('src/main.js')
  assert.ok(main.indexOf('v3-workspaces.scss') < main.indexOf('workspace-layout.scss'))
  assert.match(read('src/layouts/PortalLayout.vue'), /:data-workspace="menuOwner\(route.path\)"/)
  assert.match(read('src/components/personnel/DataState.vue'), /:data-state="state"/)
})

test('source work timeline remains available by explicit disclosure', () => {
  const source = read('src/mock/WorkTimeWindow.vue')
  assert.match(source, /<details v-if="items.length"/)
  assert.match(source, /<summary>/)
  assert.match(source, /\$emit\('select', w.workId\)/)
})
