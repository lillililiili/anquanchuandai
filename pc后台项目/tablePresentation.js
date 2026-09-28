// Presentation only: keep full values in the DOM; tooltips never change source data.
export function presentTable(table) {
  const headers = [...table.querySelectorAll('thead th')]
  const widths = headers.map(th => Number(th.dataset.width) || 160)
  table.style.setProperty('--table-width', widths.reduce((a, b) => a + b, 0) + 'px')
  headers.forEach((th, index) => { th.style.width = widths[index] + 'px' })
  table.querySelectorAll('tbody td').forEach(cell => {
    if (!cell.classList.contains('table-actions')) cell.title = cell.textContent.trim()
  })
}
export const tablePresentation = { mounted: presentTable, updated: presentTable }
export function utcTime(value) {
  if (!value) return '—'
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? value : date.toISOString().replace('T', ' ').replace(/\.\d{3}Z$/, '')
}
export function beijingTime(value) {
  if (!value) return '—'
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return value
  const parts = new Intl.DateTimeFormat('sv-SE', { timeZone: 'Asia/Shanghai', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23' }).formatToParts(date)
  const p = Object.fromEntries(parts.map(part => [part.type, part.value]))
  return `${p.year}-${p.month}-${p.day} ${p.hour}:${p.minute}:${p.second}`
}
