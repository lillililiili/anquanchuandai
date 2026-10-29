// Flatten the organization hierarchy for a searchable, collapsible sidebar.
// Missing parents and malformed cycles must never hide a visible organization.
export function organizationTreeRows(nodes, { keyword = '', collapsed = new Set() } = {}) {
  const byId = new Map(nodes.map(node => [node.id, node])), children = new Map()
  for (const node of nodes) {
    const parent = byId.has(node.parentId) && node.parentId !== node.id ? node.parentId : null
    if (!children.has(parent)) children.set(parent, [])
    children.get(parent).push(node)
  }
  const term = keyword.trim().toLocaleLowerCase(), matches = new Set()
  if (term) for (const node of nodes) {
    if (!`${node.name || ''} ${node.code || ''}`.toLocaleLowerCase().includes(term)) continue
    let current = node
    const seen = new Set()
    while (current && !seen.has(current.id)) { seen.add(current.id); matches.add(current.id); current = byId.get(current.parentId) }
  }
  const rows = [], visited = new Set()
  function visit(node, depth, hidden = false) {
    if (visited.has(node.id)) return
    visited.add(node.id)
    const childNodes = children.get(node.id) || []
    if (!hidden && (!term || matches.has(node.id))) rows.push({ node, depth, hasChildren: childNodes.length > 0, expanded: !!term || !collapsed.has(node.id) })
    for (const child of childNodes) visit(child, depth + 1, hidden || !term && collapsed.has(node.id))
  }
  for (const node of children.get(null) || []) visit(node, 0)
  for (const node of nodes) if (!visited.has(node.id)) visit(node, 0)
  return rows
}
