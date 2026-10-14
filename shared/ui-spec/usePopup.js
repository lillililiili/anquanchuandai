import { ref, shallowRef, nextTick, onBeforeUnmount, toValue } from 'vue'

const stack = []

export function usePopup(anchor, { width = 0, boundary, onClose } = {}) {
  const open = ref(false), panel = ref(null), target = shallowRef('body'), position = ref({})
  async function place() {
    if (!open.value || !anchor.value) return
    const a = anchor.value.getBoundingClientRect(), p = panel.value
    const w = Math.min(toValue(width) || Math.max(a.width, 180), window.innerWidth - 16)
    const h = Math.min(p?.scrollHeight || 280, window.innerHeight - 24)
    const below = window.innerHeight - a.bottom - 12, above = a.top - 12
    const top = below >= h || below >= above ? a.bottom + 4 : Math.max(8, a.top - h - 4)
    position.value = { width: `${w}px`, left: `${Math.max(8, Math.min(a.left, window.innerWidth - w - 8))}px`, top: `${top}px`, maxHeight: `${Math.max(96, (top > a.top ? window.innerHeight - top : a.top - 4) - 8)}px` }
  }
  function close(focus = false) {
    if (!open.value) return
    open.value = false
    const index=stack.indexOf(close); if(index>=0)stack.splice(index,1)
    document.removeEventListener('pointerdown', outside, true)
    document.removeEventListener('keydown', escape, true)
    document.removeEventListener('focusin', outside, true)
    window.removeEventListener('resize', place)
    window.removeEventListener('scroll', place, true)
    if (focus) anchor.value?.focus()
    onClose?.()
  }
  function outside(e) { if (!(toValue(boundary) || anchor.value)?.contains(e.target) && !panel.value?.contains(e.target)) close() }
  function escape(e) {
    if (e.key === 'Escape' && stack.at(-1) === close) { e.preventDefault(); e.stopImmediatePropagation(); close(true) }
  }
  async function show() {
    if (open.value) return
    target.value = anchor.value?.closest('dialog, [role="dialog"]') || 'body'
    open.value = true
    stack.push(close)
    await nextTick(); await place(); await nextTick(); await place()
    document.addEventListener('pointerdown', outside, true)
    document.addEventListener('keydown', escape, true)
    document.addEventListener('focusin', outside, true)
    window.addEventListener('resize', place)
    window.addEventListener('scroll', place, true)
  }
  function toggle() { return open.value ? close() : show() }
  onBeforeUnmount(() => close())
  return { open, panel, target, position, place, show, close, toggle }
}
