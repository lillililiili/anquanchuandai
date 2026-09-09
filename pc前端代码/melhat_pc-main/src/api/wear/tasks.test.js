import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { equipmentResultLabel, ticketStatusLabel, taskStatusLabel } from './tasks.js'

describe('work task contract', () => {
  it('does not treat missing ticket as violation', () => {
    expect(ticketStatusLabel('unverified')).toBe('待核实')
    expect(ticketStatusLabel('unverified')).not.toMatch(/违章/)
    expect(equipmentResultLabel('unknown')).toBe('未知')
    expect(taskStatusLabel('in_progress')).toBe('进行中')
  })

  it('duty and task pages exist and hide writes by permission', () => {
    const dir = dirname(fileURLToPath(import.meta.url))
    const duty = readFileSync(join(dir, '../../views/duty/index.vue'), 'utf8')
    const tasks = readFileSync(join(dir, '../../views/work-tasks/index.vue'), 'utf8')
    expect(duty).toMatch(/canEditTask/)
    expect(duty).toMatch(/listDutyOperators/)
    expect(duty).toMatch(/claimantUserId/)
    expect(tasks).toMatch(/canEditTask/)
    expect(tasks).toMatch(/acknowledgeOpenHighRisk/)
    expect(tasks).toMatch(/补齐/)
    expect(tasks).toMatch(/待核实/)
    expect(tasks).toMatch(/不是违章/)
  })
})
