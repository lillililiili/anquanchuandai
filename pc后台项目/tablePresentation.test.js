import { describe, it, expect } from 'vitest'
import { utcTime } from './tablePresentation'
import { masterColumns } from './masterColumns'

describe('admin presentation preserves source meaning', () => {
  it('normalizes offset dates to UTC without inventing missing dates', () => {
    expect(utcTime('2026-09-21T08:30:00+08:00')).toBe('2026-09-21 00:30:00')
    expect(utcTime(null)).toBe('—')
    expect(utcTime('来源待确认')).toBe('来源待确认')
  })
  it('keeps the organization column without exposing account linkage or retired area data', () => {
    const columns = masterColumns('people', { organizations: [{ id: 'o1', name: '检修班组' }], areas: [] }, {}, {}, String)
    const row = { organizationId: 'o1', areaId: 'restricted', accountId: null }
    expect(columns.map(c => c.value(row))).toEqual(['检修班组'])
    expect(row.areaId).toBe('restricted')
  })
  it('shows the actual named role scopes without duplicating or changing grants', () => {
    const row = { grants: [{ operations: ['read', 'write'], siteIds: ['s1'] }, { operations: ['read'], siteIds: ['s1', 's2'] }] }
    const original = JSON.stringify(row)
    const columns = masterColumns('roles', { sites: [{ id: 's1', name: '一号厂站' }, { id: 's2', name: '二号厂站' }] }, {}, {}, String)
    expect(columns.find(column => column.key === 'sites').value(row)).toBe('一号厂站、二号厂站')
    expect(JSON.stringify(row)).toBe(original)
  })
})
