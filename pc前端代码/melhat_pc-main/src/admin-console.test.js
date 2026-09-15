import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = dirname(fileURLToPath(import.meta.url))
const read = path => readFileSync(join(root, path), 'utf8')

describe('formal PC admin boundary', () => {
  it('keeps the big screen authenticated and legacy off by default', () => {
    expect(read('../.env.production')).toMatch(/VITE_ENABLE_LEGACY_CONSOLE\s*=\s*'false'/)
    expect(read('permission.js')).not.toMatch(/big-screen/)
    expect(read('../index.html')).not.toMatch(/AgoraRTC_N/)
  })

  it('excludes field-operation pages from the formal dynamic module graph', () => {
    const permissions = read('store/modules/permission.js')
    expect(permissions).toContain('!./../../views/index.vue')
    for (const page of ['big-screen', 'events', 'duty', 'locations', 'live', 'track', 'intercom', 'tts']) {
      expect(permissions).toContain(`!./../../views/${page}/**/*.vue`)
    }
  })

  it('provides import, export, overview and audit clients', () => {
    const admin = read('api/wear/admin.js')
    expect(admin).toMatch(/admin\/overview/)
    expect(admin).toMatch(/import-template/)
    expect(admin).toMatch(/importResource/)
    expect(read('api/wear/files.js')).toMatch(/api\/v1\/files/)
  })

  it('uses text actions in formal system-management tables', () => {
    const pages = [
      'views/system/user/index.vue',
      'views/system/role/index.vue',
      'views/system/menu/index.vue',
      'views/system/dept/index.vue',
      'views/system/post/index.vue',
      'views/system/dict/index.vue',
      'views/system/dict/data.vue',
      'views/system/config/index.vue',
      'views/system/notice/index.vue',
      'views/system/role/authUser.vue'
    ]

    for (const page of pages) {
      const source = read(page)
      const operationCell = source.split('label="操作"')[1]?.split('</el-table-column>')[0]

      expect(operationCell, page).toBeTruthy()
      expect(operationCell, page).not.toMatch(/\bicon=/)
      expect(operationCell, page).toMatch(/<el-button/)
      expect(source, page).toMatch(/fixed="right"\s+label="操作"/)
    }
  })
})
