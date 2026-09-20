import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync, readdirSync } from 'node:fs'
import { resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { parse, compileTemplate } from '@vue/compiler-sfc'
const root = fileURLToPath(new URL('../', import.meta.url))
const read = file => readFileSync(resolve(root, file), 'utf8')
function vueFiles(dir) { return readdirSync(dir, { withFileTypes: true }).flatMap(e => e.isDirectory() ? vueFiles(resolve(dir, e.name)) : e.name.endsWith('.vue') ? [resolve(dir, e.name)] : []) }
test('all pagination consumers share one component without altering page-size contracts', () => {
  const files = vueFiles(resolve(root, 'src'))
  const raw = files.filter(f => readFileSync(f, 'utf8').includes('<el-pagination'))
  assert.equal(raw.length, 1)
  assert.ok(raw[0].endsWith('AppPagination.vue'))
  const consumers = files.filter(f => readFileSync(f, 'utf8').includes('<AppPagination'))
  assert.ok(consumers.length >= 14)
  for (const file of consumers) {
    const source = readFileSync(file, 'utf8')
    const { descriptor } = parse(source)
    const compiled = compileTemplate({ source: descriptor.template.content, filename: file, id: file })
    assert.deepEqual(compiled.errors, [], file)
  }
  const pager = read('src/components/AppPagination.vue')
  assert.match(pager, /:page-size="pageSize"/)
  assert.match(pager, /:total="total"/)
  assert.match(pager, /emit\('current-change', \$event\)/)
  assert.match(pager, /prev-text="上一页" next-text="下一页"/)
})
test('workspace has bounded desktop lists and accessible zoom fallback', () => {
  const css = read('src/styles/workspace-layout.scss')
  for (const name of ['table-scroll', 'equipment-table-wrap', 'event-table-scroll', 's2-material-grid', 'workspace-list-scroll']) assert.ok(css.includes(name))
  assert.match(css, /max-height:759px/)
  assert.match(css, /position:sticky/)
  assert.match(css, /\.el-dialog__body[^}]*overflow:auto/)
  assert.match(read('src/layouts/PortalLayout.vue'), /aria-label="页面内容"/)
})

test('unselected detail panes do not reserve empty columns', () => {
  for (const file of ['personnel/PersonnelView.vue', 'alarms/AlarmsView.vue', 'materials/MaterialsView.vue', 'location/FenceView.vue']) {
    const source = read('src/views/' + file)
    assert.match(source, /'has-selection': !!selectedId/)
    assert.match(source, /<aside v-if="selectedId"/)
  }
  assert.match(read('src/mock/WorkView.vue'), /v-if="standalone \|\| workId"/)
})

test('dispatch panels stack independently rather than sharing tall rows', () => {
  const source = read('src/mock/DispatchView.vue')
  assert.equal((source.match(/class="dispatch-columns"/g) || []).length, 1)
  assert.equal((source.match(/class="dispatch-stack"/g) || []).length, 2)
  assert.ok(source.indexOf('最近会话记录') < source.indexOf('当前本地会话'))
})
