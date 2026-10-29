import { describe, expect, it } from 'vitest'
import { organizationTreeRows } from './organizationTree'
const nodes = [
  { id: 'parent', name: '运行部' },
  { id: 'child', parentId: 'parent', name: '一班' },
  { id: 'leaf', parentId: 'child', name: '巡检组', code: 'TEAM-A' },
  { id: 'other', name: '维护部' },
]
describe('organization tree navigation', () => {
  it('keeps a collapsed branch hidden instead of promoting its descendants to roots', () => {
    const rows = organizationTreeRows(nodes, { collapsed: new Set(['parent']) })
    expect(rows.map(row => row.node.id)).toEqual(['parent', 'other'])
    expect(rows[0].expanded).toBe(false)
  })
  it('reveals search matches with their ancestors even inside collapsed branches', () => {
    const rows = organizationTreeRows(nodes, { keyword: 'team-a', collapsed: new Set(['parent', 'child']) })
    expect(rows.map(row => [row.node.id, row.depth])).toEqual([['parent', 0], ['child', 1], ['leaf', 2]])
    expect(rows[0].expanded).toBe(true)
    expect(organizationTreeRows(nodes, { keyword: '不存在' })).toEqual([])
  })
  it('keeps orphaned records visible and terminates cycles without duplicate nodes', () => {
    const rows = organizationTreeRows([
      { id: 'orphan', parentId: 'hidden' }, { id: 'self', parentId: 'self' },
      { id: 'a', parentId: 'b' }, { id: 'b', parentId: 'a' },
    ])
    expect(rows.map(row => row.node.id)).toEqual(['orphan', 'self', 'a', 'b'])
    expect(organizationTreeRows([{ id: 'a', parentId: 'b', name: '匹配' }, { id: 'b', parentId: 'a' }], { keyword: '匹配' })).toHaveLength(2)
  })
})
