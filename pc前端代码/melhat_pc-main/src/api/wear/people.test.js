import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

describe('people selector contract', () => {
  it('does not query the system user list', () => {
    const dir = dirname(fileURLToPath(import.meta.url))
    const source = readFileSync(join(dir, 'people.js'), 'utf8')
    expect(source).not.toMatch(/\/system\/user\/list/)
    expect(source).toMatch(/\/api\/v1\/people\/options/)
  })
})
