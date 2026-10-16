import { onScopeDispose, shallowRef } from 'vue'

export const confirmation = shallowRef(null)
let pending

export function finishConfirmation(accepted = false) {
  const current = pending
  pending = undefined
  confirmation.value = null
  current?.resolve(accepted)
}

export function requestConfirmation(owner, options = {}) {
  if (pending?.owner === owner) return pending.promise
  // A newer action must not inherit another form's discard decision.
  finishConfirmation(false)
  let resolve
  const promise = new Promise(done => { resolve = done })
  pending = { owner, promise, resolve }
  confirmation.value = {
    title: '放弃未保存的修改？',
    message: '本次修改尚未保存，放弃后将无法恢复。',
    cancelText: '继续编辑', confirmText: '放弃修改', ...options,
  }
  return promise
}

export function cancelConfirmation(owner) {
  if (pending?.owner === owner) finishConfirmation(false)
}

export function useConfirmation() {
  const owner = Symbol('form-confirmation')
  onScopeDispose(() => cancelConfirmation(owner))
  return options => requestConfirmation(owner, options)
}
