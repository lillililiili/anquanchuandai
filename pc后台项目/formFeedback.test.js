import { afterEach, describe, expect, it } from 'vitest'
import { effectScope, nextTick, ref } from 'vue'
import { useFormFeedback } from './formFeedback'
import { confirmation, finishConfirmation, useConfirmation } from './confirmation'

const scopes = []
function scoped(work) { const scope = effectScope(); scopes.push(scope); return { scope, value: scope.run(work) } }
afterEach(() => { scopes.splice(0).forEach(scope => scope.stop()); finishConfirmation(false) })

describe('discard confirmation', () => {
  it('waits for a choice, defaults to cancellation and does not stack repeated close requests', async () => {
    const { value: confirm } = scoped(useConfirmation)
    const first = confirm(), repeated = confirm()
    expect(repeated).toBe(first)
    expect(confirmation.value.confirmText).toBe('放弃修改')
    finishConfirmation()
    expect(await first).toBe(false)
    expect(confirmation.value).toBe(null)
    const next = confirm(); finishConfirmation(true)
    expect(await next).toBe(true)
  })
  it('never carries a discard choice into a different form', async () => {
    const a = scoped(useConfirmation), b = scoped(useConfirmation)
    const first = a.value(), second = b.value()
    expect(await first).toBe(false)
    a.scope.stop()
    expect(confirmation.value).not.toBe(null)
    finishConfirmation(true)
    expect(await second).toBe(true)
  })
  it('cancels a pending navigation when its form is destroyed', async () => {
    const { scope, value: confirm } = scoped(useConfirmation)
    const choice = confirm(); scope.stop()
    expect(await choice).toBe(false)
    expect(confirmation.value).toBe(null)
  })
})

describe('field feedback', () => {
  function setup(value) {
    const form = ref(value), failure = ref(null)
    const { value: feedback } = scoped(() => useFormFeedback(form, () => failure.value, 'field-', { localStart: 'startsAt' }))
    return { form, failure, ...feedback }
  }
  it('shows server fields inline and clears only the edited field', async () => {
    const f = setup({ code: '', name: '' })
    f.failure.value = { message: '校验失败', fields: { code: '编号重复', name: '请填写姓名' } }
    await nextTick()
    expect(f.formError.value).toBe('')
    expect(f.errors.value).toEqual({ code: '编号重复', name: '请填写姓名' })
    f.form.value.code = 'new-code'
    expect(f.errors.value).toEqual({ name: '请填写姓名' })
  })
  it('keeps network and unknown-field errors visible without discarding entered values', async () => {
    const f = setup({ code: 'draft' })
    f.failure.value = { message: '后端未连接，修改未保存' }; await nextTick()
    expect(f.formError.value).toBe('后端未连接，修改未保存')
    f.failure.value = { message: '校验失败', fields: { unsupported: '关联数据已变更' } }; await nextTick()
    expect(f.formError.value).toBe('关联数据已变更')
    expect(f.form.value.code).toBe('draft')
  })
  it('maps nested and transformed field errors and clears them when edited', async () => {
    const f = setup({ bindings: [{ roleId: '' }], localStart: '' })
    f.failure.value = { fields: { 'bindings[0].roleId': '请选择角色', startsAt: '时间无效' } }; await nextTick()
    expect(f.errors.value).toEqual({ bindings: '请选择角色', startsAt: '时间无效' })
    expect(f.formError.value).toBe('')
    f.form.value.bindings[0].roleId = 'member'; f.form.value.localStart = '2026-10-14T10:00'
    expect(f.errors.value).toEqual({})
  })
})
