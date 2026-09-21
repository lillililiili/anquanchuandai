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
