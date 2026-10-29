// Keep the asset/people pair left of the title; overflow never moves them to the right.
export function fitAdminNavigation(widths, leftWidth, rightWidth, moreWidth, gap = 4) {
  const occupied = values => values.reduce((sum, width) => sum + width, 0) + Math.max(0, values.length - 1) * gap
  for (let count = widths.length; count >= 0; count--) {
    const leftCount = Math.min(2, count)
    const left = widths.slice(0, leftCount), right = widths.slice(leftCount, count)
    if (count < widths.length) right.push(moreWidth)
    if (occupied(left) <= leftWidth && occupied(right) <= rightWidth) return { visibleCount: count, leftCount }
  }
  return { visibleCount: 0, leftCount: 0 }
}

// The proposed site is committed only after the existing leave guard accepts it.
export async function changeSiteAfterConfirmation({ current, next, confirm, commit }) {
  if (next === current) return false
  if (!await confirm()) return false
  await commit(next)
  return true
}
