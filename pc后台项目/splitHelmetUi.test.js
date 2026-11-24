import { describe, it, expect } from 'vitest'
import { createSSRApp, h } from 'vue'
import { renderToString } from 'vue/server-renderer'
import DeviceEditor from './components/DeviceEditor.vue'
import { splitHelmetTelemetry } from '../shared/split-helmet.mjs'

async function form(row) {
  const app = createSSRApp(DeviceEditor, { row })
  app.component('UiSelect', { setup(_, { attrs, slots }) { return () => h('select', attrs, slots.default?.()) } })
  app.component('UiDatePicker', { setup(_, { attrs }) { return () => h('input', { ...attrs, type: 'date' }) } })
  return renderToString(app)
}
describe('isolated split helmet administration UI', () => {
  it('offers split registration beside integrated helmets and protects persisted protocol identifiers', async () => {
    const create = await form()
    expect(create).toContain('value="SPLIT_HELMET"')
    expect(create).toContain('一体式安全帽直连')
    const edit = await form({ source: 'SPLIT_HELMET', type: 'HELMET', code: 'ASSET-1', sn: 'SN-2', deviceNumber: 'helmet-sn-3', name: '分体帽', version: 1 })
    expect(edit).toContain('中间件设备编号（helmetSn）')
    expect(edit).toMatch(/id="device-deviceNumber"[^>]*disabled/)
    expect(edit).toMatch(/id="device-code"[^>]*disabled/)
    expect(edit).not.toContain('value="SPLIT_HELMET"')
  })
  it('renders temperature and TF observations independently without inventing measurement units', () => {
    const now = Date.now(), reportedAt = new Date(now).toISOString()
    const fields = splitHelmetTelemetry({ online: false, temperature: '25.3', temperatureReportedAt: reportedAt, temperatureFreshness: 'CURRENT', tfEnable: '1', tfEnableReportedAt: '2020-01-01', tfEnableFreshness: 'STALE', storageAvailable: '2G', storageAvailableReportedAt: reportedAt, storageAvailableFreshness: 'CURRENT' }, now).fields
    expect(fields.find(row => row.key === 'temperature')).toMatchObject({ value: '25.3（单位未提供）', status: '近期上报', reportedAt })
    expect(fields.find(row => row.key === 'tfEnable').status).toBe('最后上报')
    expect(fields.find(row => row.key === 'storageAvailable').status).toBe('近期上报')
  })
})
