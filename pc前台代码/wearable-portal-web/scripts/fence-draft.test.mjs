import test from 'node:test'
import assert from 'node:assert/strict'
import { validateFenceDraft } from '../src/utils/fence-draft.js'
const triangle = [[117.142,36.665],[117.147,36.664],[117.143,36.661]]
const base = { name:'区域', ruleType:'DENY_ENTRY', appliesTo:'HELMET', nodes:triangle }
test('valid triangle saves without a separate drawing-complete flag', () => {
  const result = validateFenceDraft(base)
  assert.equal(result.valid,true)
  assert.equal(result.ring.length,4)
  assert.deepEqual(result.ring[0],result.ring[3])
})
test('empty fields report all missing values without discarding the geometry', () => {
  const result = validateFenceDraft({ nodes:triangle })
  assert.deepEqual(Object.keys(result.fields),['name','ruleType','appliesTo'])
  assert.equal(result.geometryError,'')
  assert.equal(result.valid,false)
})
test('crossing and insufficient nodes reject; corrected triangle clears old error', () => {
  assert.ok(validateFenceDraft({...base,nodes:[[0,0],[1,1],[0,1],[1,0]]}).geometryError)
  assert.ok(validateFenceDraft({...base,nodes:triangle.slice(0,2)}).geometryError)
  assert.equal(validateFenceDraft(base).geometryError,'')
  assert.equal(validateFenceDraft({...base,name:'  '}).valid,false)
})
