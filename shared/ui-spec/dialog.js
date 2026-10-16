export const DIALOG_SIZES = ['confirm', 'compact', 'regular', 'wide']
export function dialogSize(size, wide = false) {
  return DIALOG_SIZES.includes(size) ? size : wide ? 'wide' : 'regular'
}
export function shouldCloseDialog(event) {
  return event.key === 'Escape' && !event.defaultPrevented
}
export function restoreDialogFocus(target) {
  if (target?.isConnected && !target.disabled) target.focus({ preventScroll: true })
}
