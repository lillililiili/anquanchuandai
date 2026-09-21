import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
test('fence creation uses mouse drawing and has no existing-fence edit entry', () => {
  const editor = readFileSync(new URL('../src/mock/FenceEditor.vue', import.meta.url), 'utf8')
  assert.match(editor, /title="新增围栏"/)
  assert.match(editor, /完成绘制/)
  assert.match(editor, /normalizeRing\(draft.value.nodes\)/)
  assert.doesNotMatch(editor, /start\(item\)|编辑围栏|添加坐标节点|编辑节点/)
  assert.match(editor, /v-if="open"/)
  assert.match(editor, /destroy-on-close/)
})
test('fence canvas includes basemap, proper initial view, visible vertices and cleanup', () => {
  const canvas = readFileSync(new URL('../src/mock/FenceCanvas.vue', import.meta.url), 'utf8')
  assert.match(canvas, /createBasemapLayers\(\)/)
  assert.match(canvas, /layers: \[street,/)
  assert.match(canvas, /fromLonLat\(MAP_CENTER\)/)
  assert.match(canvas, /new Point\(point\)/)
  assert.match(canvas, /map.on\('singleclick'/)
  assert.match(canvas, /重新加载底图/)
  assert.match(canvas, /observer\?\.disconnect/)
  assert.match(canvas, /map\?\.dispose/)
})
