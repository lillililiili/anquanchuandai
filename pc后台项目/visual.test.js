// @vitest-environment node
import { describe, it, expect } from 'vitest'
import { readFileSync, existsSync } from 'node:fs'

const read = name => readFileSync(new URL(name, import.meta.url), 'utf8')
const exists = name => existsSync(new URL(name, import.meta.url))
const luminance = hex => {
  const rgb = hex.match(/\w\w/g).map(v => parseInt(v, 16) / 255).map(v => v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4)
  return rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722
}
describe('admin visual foundation', () => {
  it('keeps readable foreground palette on solid surfaces', () => {
    for (const [fg, bg] of [['142b55','ffffff'], ['586b83','ffffff'], ['ffffff','2563eb'], ['08778c','e5f9fc'], ['7c3aed','f2ecff'], ['b42337','ffffff'], ['147a53','ffffff']]) {
      const values = [luminance(fg), luminance(bg)].sort((a,b) => b-a)
      expect((values[0]+0.05)/(values[1]+0.05), fg).toBeGreaterThanOrEqual(4.5)
    }
  })
  it('ships the nine local compressed illustrations', () => {
    for (const name of ['login-showroom','showroom-banner','helmet','harness','watch','theme-people','theme-maintenance','theme-access','state-empty']) expect(exists(`assets/visual/${name}.webp`)).toBe(true)
  })
  it('keeps styles layered with reduced-motion and keyboard focus rules', () => {
    expect(read('styles.css').match(/@import/g)).toHaveLength(5)
    const styles = ['base','shell','components','pages'].map(n => read(`styles/${n}.css`)).join('\n')
    expect(styles).toContain('prefers-reduced-motion')
    expect(styles).toContain('focus-visible')
    expect(styles).not.toMatch(/https?:\/\//)
  })
})
