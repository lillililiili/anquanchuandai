// @vitest-environment node
import { describe, it, expect } from 'vitest'
import { readFileSync, readdirSync } from 'node:fs'
import { createAdminService } from './service'

function service() {
  const map = new Map()
  return createAdminService({ storage: { getItem: k => map.get(k), setItem: (k,v) => map.set(k,v), removeItem: k => map.delete(k) }, delay: 0 })
}
describe('account login and business wording', () => {
  it('rejects empty, wrong and unknown credentials', () => {
    const api = service()
    for (const [name, password] of [['admin', undefined], ['admin', 'wrong'], ['missing', 'Admin@2026'], ['', '']]) {
      expect(() => api.login(name, password)).toThrow('账号或密码错误')
      expect(api.identity()).toBe(null)
    }
  })
  it.each([['admin','demo-system'],['siteadmin','demo-site'],['assetadmin','demo-asset'],['auditor','demo-audit']])('maps %s to its existing scope', async (name, id) => {
    const api = service()
    expect(api.login(name, 'Admin@2026').id).toBe(id)
    expect((await api.query('context')).data.sites.length).toBeGreaterThan(0)
    api.logout(); expect(api.identity()).toBe(null)
  })
  it('keeps standard labeled inputs without role selection', () => {
    const source = readFileSync(new URL('./views/Login.vue', import.meta.url), 'utf8')
    expect(source).toContain('autocomplete="username"')
    expect(source).toContain('autocomplete="current-password"')
    expect(source).toContain('账号和密码')
    expect(source).not.toMatch(/type="radio"|login-boundary|identity-option/)
    expect(source).toContain('class="password-toggle"')
    expect(source).toContain('visible ? View : Hide')
    expect(source).toContain('padding-right: 48px')
  })
  it('uses plain operator wording and keeps simulation notices', () => {
    function walk(dir) {
      for (const entry of readdirSync(dir, { withFileTypes: true })) {
        const url = new URL(entry.name + (entry.isDirectory() ? '/' : ''), dir)
        if (entry.isDirectory()) walk(url)
        else if (entry.name.endsWith('.vue')) expect(readFileSync(url, 'utf8')).not.toMatch(/同口径|新鲜度|实例装配|\bA[0-6]\b|item\.stage|route\.meta\.stage/)
      }
    }
    walk(new URL('./views/', import.meta.url))
    walk(new URL('./components/', import.meta.url))
    expect(readFileSync(new URL('./views/Integrations.vue', import.meta.url), 'utf8')).toContain('确认导入模拟样本')
    expect(readFileSync(new URL('./auditData.js', import.meta.url), 'utf8')).toContain('模拟数据')
    expect(readFileSync(new URL('./views/Overview.vue', import.meta.url), 'utf8')).toContain('查看明细')
  })
})
