import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { readFileSync } from 'node:fs'
import { compileScript, parse } from '@vue/compiler-sfc'
import * as Vue from 'vue'
import { featureDraft, featurePayload } from './deviceFeatureForm'
import { deviceFeatureRows } from './deviceFeaturePresentation'

const state = {}
const ModalPanel = { props: ['open'], setup: (props, { slots }) => () => props.open ? Vue.h('section', { role: 'dialog' }, slots.default?.()) : null }
const { descriptor } = parse(readFileSync(new URL('./components/DeviceFeatureEditor.vue', import.meta.url), 'utf8'))
const compiled = compileScript(descriptor, { id: 'feature-editor', inlineTemplate: true, genDefaultAs: 'Component' }).content
const executable = compiled.replace(/^import\s+\{([^}]+)\}\s+from\s+['"]vue['"];?\s*$/gm, (_, names) => `const {${names.replace(/\s+as\s+/g, ':')}} = Vue`)
  .replace(/^import[^\n]+$/gm, '')
// Exercise the real component's model update callbacks and asynchronous lifecycle.
// DOM-specific v-model listeners and the native dialog are covered by browser QA.
const Component = new Function('Vue', 'getAdminProvider', 'useAdminStore', 'useConfirmation', 'beijingTime', 'deviceFeatureRows', 'featureDraft', 'featurePayload', 'ModalPanel', executable + '\nreturn Component')(
  { ...Vue, vModelText: {}, vModelSelect: {} }, () => state.provider, () => state.store, () => state.confirm, value => value, deviceFeatureRows, featureDraft, featurePayload, ModalPanel)
const renderer = Vue.createRenderer({
  createElement: type => ({ type, children: [], props: {}, parent: null }),
  createText: text => ({ type: 'text', text }), createComment: text => ({ type: 'comment', text }),
  setText: (node, text) => { node.text = text }, setElementText: (node, text) => { node.text = text; node.children = [] },
  patchProp: (node, key, old, value) => { node.props[key] = value },
  parentNode: node => node.parent, nextSibling: node => node.parent?.children[node.parent.children.indexOf(node) + 1] || null,
  insert(node, parent, anchor = null) { if (node.parent) node.parent.children.splice(node.parent.children.indexOf(node), 1); node.parent = parent; const index = anchor ? parent.children.indexOf(anchor) : -1; if (index < 0) parent.children.push(node); else parent.children.splice(index, 0, node) },
  remove(node) { if (node.parent) { node.parent.children.splice(node.parent.children.indexOf(node), 1); node.parent = null } },
})
const find = (node, predicate) => predicate(node) ? node : node.children?.map(child => find(child, predicate)).find(Boolean)
const node = type => find(root, item => item.type === type)
const dialog = () => find(root, item => item.props?.role === 'dialog')
const flush = async () => { await Promise.resolve(); await Vue.nextTick(); await Promise.resolve(); await Vue.nextTick() }
let root, app, props, allowed, listeners, record, saved
const publish = kind => { for (const listener of listeners) listener({ kind }) }
async function open() { await node('button').props.onClick(); await flush() }
function mount() { root = { children: [] }; app = renderer.createApp({ setup: () => () => Vue.h(Component, { ...props, onSaved: saved }) }); app.mount(root) }
function editStatus() {
  const selects = node('fieldset').children[1].children
  for (const [index, value] of ['SUPPORTED', 'CONNECTED', 'AVAILABLE'].entries()) {
    find(selects[index], item => item.type === 'select').props['onUpdate:modelValue'](value)
  }
  node('fieldset').props.onChange()
}
async function submit() { await node('form').props.onSubmit({ preventDefault() {} }); await flush() }
beforeEach(() => {
  allowed = true; listeners = new Set(); saved = vi.fn()
  record = { id: 'belt-1', siteId: 'site-1', name: '隔离测试设备', source: 'DIRECT_BELT', type: 'BELT', version: 4, featureManagement: { version: 2, editable: true },
    featureStates: Object.fromEntries(['height', 'temperature'].map(key => [key, { supported: true, configurable: true, verified: false, available: false, reason: '设备数据待确认', integrationStatus: 'CONNECTED' }])) }
  props = Vue.reactive({ device: structuredClone(record) })
  state.store = Vue.reactive({ siteId: 'site-1', leaveGuard: null })
  state.confirm = vi.fn().mockResolvedValue(true)
  state.provider = { canAny: vi.fn(() => allowed), query: vi.fn().mockImplementation(async () => ({ data: structuredClone(record) })), execute: vi.fn().mockResolvedValue({}),
    subscribe: listener => { listeners.add(listener); return () => listeners.delete(listener) } }
})
afterEach(() => app?.unmount())

describe('feature editor save and authorization', () => {
  it('uses freshly queried version and saves through the remote command', async () => {
    record.version = 9; mount(); await open(); editStatus(); await submit()
    expect(state.provider.execute).toHaveBeenCalledWith('devices.features', expect.objectContaining({ siteId: 'site-1', id: 'belt-1', expectedVersion: 9, operationId: expect.any(String), data: { feature: 'height', support: 'SUPPORTED', connection: 'CONNECTED', availability: 'AVAILABLE' } }))
    expect(saved).toHaveBeenCalledOnce(); expect(dialog()).toBeUndefined(); expect(state.store.leaveGuard).toBeNull()
  })
  it('blocks old servers and users without asset permission', async () => {
    props.device.featureManagement = undefined; mount(); await open(); expect(state.provider.query).not.toHaveBeenCalled()
    props.device.featureManagement = record.featureManagement; allowed = false; publish('revision'); await flush(); await open()
    expect(node('button').props.disabled).toBe(true); expect(state.provider.query).not.toHaveBeenCalled()
  })
  it('revokes an open form and refuses the old submit handler', async () => {
    mount(); await open(); editStatus(); const handler = node('form').props.onSubmit
    allowed = false; publish('authorization'); await flush(); await handler({ preventDefault() {} })
    expect(dialog()).toBeUndefined(); expect(state.provider.execute).not.toHaveBeenCalled()
  })
  it('ignores late responses after the selected device changes', async () => {
    let resolve; state.provider.query.mockReturnValue(new Promise(done => { resolve = done }))
    mount(); const pending = node('button').props.onClick(); props.device.id = 'belt-2'; await flush()
    resolve({ data: structuredClone(record) }); await pending; await flush()
    expect(dialog()).toBeUndefined(); expect(state.store.leaveGuard).toBeNull()
  })
  it('keeps the pending read and draft when telemetry refreshes the same device', async () => {
    let resolve; state.provider.query.mockReturnValue(new Promise(done => { resolve = done }))
    mount(); const pending = node('button').props.onClick()
    props.device = { ...structuredClone(record), battery: 41 }; await flush()
    expect(state.provider.query.mock.calls[0][2].signal.aborted).toBe(false)
    resolve({ data: structuredClone(record) }); await pending; await flush(); editStatus()
    props.device = { ...structuredClone(record), battery: 40 }; await flush()
    expect(dialog()).toBeTruthy(); expect(state.store.leaveGuard).toBeTypeOf('function')
    await submit()
    expect(state.provider.execute).toHaveBeenCalledWith('devices.features', expect.objectContaining({ data: expect.objectContaining({ support: 'SUPPORTED', connection: 'CONNECTED', availability: 'AVAILABLE' }) }))
  })
  it('closes the draft when refreshed device permissions are revoked', async () => {
    mount(); await open(); editStatus(); const handler = node('form').props.onSubmit
    props.device = { ...structuredClone(record), featureManagement: { version: 2, editable: false } }; await flush()
    await handler({ preventDefault() {} })
    expect(dialog()).toBeUndefined(); expect(state.provider.execute).not.toHaveBeenCalled()
  })
  it('keeps failed saves visible and reuses the operation ID for a transport retry', async () => {
    state.provider.execute.mockRejectedValueOnce(Error('网络中断')); mount(); await open(); editStatus(); await submit()
    expect(dialog()).toBeTruthy(); expect(saved).not.toHaveBeenCalled(); expect(find(root, item => item.props?.role === 'alert').text).toBe('网络中断')
    await submit(); expect(state.provider.execute.mock.calls[0][1]).toEqual(state.provider.execute.mock.calls[1][1]); expect(saved).toHaveBeenCalledOnce()
  })
  it('requires a fresh read after a version conflict', async () => {
    state.provider.execute.mockRejectedValue(Object.assign(Error('对象已变化，请重新读取'), { code: 409, errorCode: 'VERSION_CONFLICT' }))
    mount(); await open(); editStatus(); await submit(); await submit()
    expect(state.provider.execute).toHaveBeenCalledTimes(1); expect(dialog()).toBeTruthy(); expect(saved).not.toHaveBeenCalled()
    record.version = 5; await find(root, item => item.type === 'button' && item.text === '重新读取配置').props.onClick(); await flush()
    state.provider.execute.mockResolvedValue({}); editStatus(); await submit()
    expect(state.provider.execute.mock.calls[1][1].expectedVersion).toBe(5)
  })
  it('restores the selected feature when discarding edits is cancelled', async () => {
    mount(); await open(); editStatus(); state.confirm.mockResolvedValue(false)
    const event = { target: { value: 'temperature' } }; await node('select').props.onChange(event); await flush()
    expect(event.target.value).toBe('height'); await submit()
    expect(state.provider.execute.mock.calls[0][1].data.feature).toBe('height')
  })
})
