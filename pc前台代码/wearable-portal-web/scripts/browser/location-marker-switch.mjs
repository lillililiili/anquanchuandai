import { chromium } from 'playwright'
import { mkdirSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const origin = 'http://127.0.0.1:5179'
const out = join(dirname(fileURLToPath(import.meta.url)), '../../output/playwright')
mkdirSync(out, { recursive: true })

function mapState() {
  const scene = document.querySelector('.amap-scene')
  const s = scene?.__vueParentComponent?.setupState
  if (!s?.olMap) return { ready: false }
  const map = s.olMap
  const size = map.getSize() || [0, 0]
  const markers = s.markerSource?.getFeatures() || []
  const points = s.pointOverlays || []
  const card = document.querySelector('.s2-position-card')?.getBoundingClientRect()
  const canvas = document.querySelector('.s2-map-target')?.getBoundingClientRect()
  const marker = markers[0]
  let pixel = null, underCard = null
  if (marker && canvas) {
    pixel = map.getPixelFromCoordinate(marker.getGeometry().getCoordinates())
    const x = canvas.left + pixel[0], y = canvas.top + pixel[1]
    underCard = !!(card && x >= card.left && x <= card.right && y >= card.top && y <= card.bottom)
    pixel = { x: Math.round(x), y: Math.round(y), mapX: Math.round(pixel[0]), mapY: Math.round(pixel[1]) }
  }
  return {
    ready: true,
    points: points.length,
    markers: markers.length,
    title: document.querySelector('.s2-position-card h2')?.textContent || '',
    size,
    zoom: map.getView().getZoom(),
    pixel,
    underCard,
    card: card ? { left: Math.round(card.left), right: Math.round(card.right), top: Math.round(card.top), width: Math.round(card.width) } : null
  }
}

const browser = await chromium.launch({ headless: true })
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } })
const errors = []
page.on('pageerror', error => errors.push(error.message))
await page.goto(origin + '/#/login', { waitUntil: 'domcontentloaded' })
await page.getByRole('textbox', { name: '账号', exact: true }).waitFor()
if (await page.getByRole('button', { name: '用户菜单' }).count() === 0) {
  await page.getByRole('textbox', { name: '账号', exact: true }).fill('admin')
  await page.getByRole('textbox', { name: '密码', exact: true }).fill('Admin@2026')
  await page.getByRole('button', { name: '登录', exact: true }).click()
  await page.getByRole('button', { name: '用户菜单' }).waitFor()
}
await page.goto(origin + '/#/location?tab=live&siteId=mock-site-1')
await page.locator('.s2-list-row').first().waitFor()
await page.locator('.s2-map-caption').filter({ hasText: '预置位置' }).waitFor({ timeout: 25000 })

const results = []
async function selectRow(index, waitMarker) {
  await page.locator('.s2-list-row').nth(index).click()
  await page.waitForTimeout(900)
  const state = await page.evaluate(mapState)
  results.push({ index, ...state })
  if (!state.ready) throw new Error('Map not ready after selecting row ' + index)
  if (state.points < 1) throw new Error('Map points disappeared after selecting row ' + index)
  if (waitMarker && state.markers !== 1) throw new Error('Selected person should show a gold marker, row ' + index)
  if (waitMarker && state.underCard) throw new Error('Selected marker is hidden under the detail card, row ' + index)
  return state
}

await selectRow(0, true)
await page.screenshot({ path: join(out, 'location-switch-person-01.png') })
const missing = await selectRow(1, false)
if (missing.markers !== 0) throw new Error('Person without a plottable location should not get a gold marker')
if (!missing.title.includes('人员1-02')) throw new Error('Wrong person after second click')
if (!(await page.locator('.s2-position-card').innerText()).includes('暂无可确认位置')) throw new Error('Missing no-location copy')
await page.screenshot({ path: join(out, 'location-switch-person-02.png') })
await selectRow(0, true)
await selectRow(4, true)
await selectRow(6, true)
await selectRow(0, true)
await page.screenshot({ path: join(out, 'location-switch-person-01-again.png') })
await page.setViewportSize({ width: 390, height: 844 })
await page.waitForTimeout(600)
const mobile = await page.evaluate(() => ({ client: document.documentElement.clientWidth, scroll: document.documentElement.scrollWidth }))
if (mobile.scroll > mobile.client + 2) throw new Error('Mobile overflow')
await browser.close()
if (errors.length) throw new Error(errors.join('\n'))
console.log(JSON.stringify({ ok: true, results, mobile }, null, 2))
