import { describe, it, expect } from 'vitest'
import { utcTime } from './tablePresentation'
import { masterColumns } from './masterColumns'

describe('admin presentation preserves source meaning', () => {
  it('normalizes offset dates to UTC without inventing missing dates', () => {
    expect(utcTime('2026-09-21T08:30:00+08:00')).toBe('2026-09-21 00:30:00')
    expect(utcTime(null)).toBe('—')
    expect(utcTime('来源待确认')).toBe('来源待确认')
  })
  it('keeps organization and area in separate columns and does not resolve unavailable names', () => {
    const columns = masterColumns('people', { organizations: [{ id: 'o1', name: '检修班组' }], areas: [] }, {}, {}, String)
    const row = { organizationId: 'o1', areaId: 'restricted', accountId: null }
    expect(columns.map(c => c.value(row))).toEqual(['检修班组', '区域未关联/已停用', '无登录账号'])
    expect(row.areaId).toBe('restricted')
  })
  it('keeps actual multi-value role scopes as a count with a detail entry', () => {
    const row = { grants: [{ operations: ['read', 'write'], siteIds: ['s1'] }, { operations: ['read'], siteIds: ['s2'] }] }
    const original = JSON.stringify(row)
    const columns = masterColumns('roles', {}, {}, {}, String)
    expect(columns[0].value(row)).toBe(2)
    expect(JSON.stringify(row)).toBe(original)
  })
})
