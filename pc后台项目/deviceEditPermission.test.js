import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { readFileSync } from 'node:fs'
import { compileScript, parse } from '@vue/compiler-sfc'
import * as Vue from 'vue'
import { createRenderer, defineComponent, h, nextTick, reactive } from 'vue'

const state = { provider: null, store: null, editor: null }
const ModalPanel = { props: ['open'], setup: (props, { slots }) => () => props.open ? h('section', { role: 'dialog' }, slots.default?.()) : null }
const DeviceEditor = { props: ['row', 'error'], emits: ['save', 'close', 'dirty'], setup(props, { emit }) { state.editor = { props, emit }; return () => h('div', { class: 'editor' }, props.error?.message || props.row?.name) } }
// Node Vitest transforms .vue imports for SSR. Compile this real SFC explicitly
// for the client renderer so handlers and reactive lifecycle actually execute.
const { descriptor } = parse(readFileSync(new URL('./components/DeviceEditPanel.vue', import.meta.url), 'utf8'))
const compiled = compileScript(descriptor, { id: 'device-permission', inlineTemplate: true, genDefaultAs: 'Component' }).content
const executable = compiled.replace(/^import\s+\{([^}]+)\}\s+from\s+['"]vue['"];?\s*$/gm, (_, names) => `const {${names.replace(/\s+as\s+/g, ':')}} = Vue`)
  .replace(/^import[^\n]+$/gm, '')
const DeviceEditPanel = new Function('Vue', 'getAdminProvider', 'useAdminStore', 'useConfirmation', 'ModalPanel', 'DeviceEditor', executable + '\nreturn Component')(
  Vue, () => state.provider, () => state.store, () => vi.fn().mockResolvedValue(true), ModalPanel, DeviceEditor)

// Mount the real Vue entry component without a browser DOM. We invoke its real
// click handler and child save event; only the form body and transport are stubs.
const renderer = createRenderer({
  createElement: type => ({ type, children: [], props: {}, parent: null }),
  createText: text => ({ type: 'text', text }), createComment: text => ({ type: 'comment', text }),
  setText: (node, text) => { node.text = text }, setElementText: (node, text) => { node.text = text; node.children = [] },
  patchProp: (node, key, old, value) => { node.props[key] = value },
  parentNode: node => node.parent, nextSibling: node => node.parent?.children[node.parent.children.indexOf(node) + 1] || null,
  insert(node, parent, anchor = null) { if (node.parent) node.parent.children.splice(node.parent.children.indexOf(node), 1); node.parent = parent; const index = anchor ? parent.children.indexOf(anchor) : -1; if (index < 0) parent.children.push(node); else parent.children.splice(index, 0, node) },
  remove(node) { if (node.parent) { node.parent.children.splice(node.parent.children.indexOf(node), 1); node.parent = null } },
})
const find = (node, predicate) => predicate(node) ? node : node.children?.map(child => find(child, predicate)).find(Boolean)
let app, root, allowed, listeners, props
const flush = async () => { await Promise.resolve(); await nextTick(); await Promise.resolve(); await nextTick() }
const emit = kind => { for (const listener of listeners) listener({ kind }) }
const trigger = () => find(root, node => node.type === 'button')
const dialog = () => find(root, node => node.props?.role === 'dialog')
function mount() {
  root = { children: [] }
  app = renderer.createApp(defineComponent({ setup: () => () => h(DeviceEditPanel, props) }))
  app.mount(root)
}
beforeEach(() => {
  allowed = true; listeners = new Set(); state.editor = null
  state.store = reactive({ siteId: 'site-1', leaveGuard: null })
  state.provider = {
    canAny: vi.fn((operation, site) => allowed && operation === 'assets:write' && site === 'site-1'),
    query: vi.fn().mockResolvedValue({ data: { availability: 'AVAILABLE' } }),
    execute: vi.fn().mockResolvedValue({ data: {} }), invalidate: vi.fn(),
    subscribe: listener => { listeners.add(listener); return () => listeners.delete(listener) },
  }
  props = reactive({ device: { id: 'qa-device', name: 'QA asset', version: 3, writable: true }, disabled: false })
})
afterEach(() => { app?.unmount(); app = null })

describe('device editor permission boundary', () => {
  it('disables a readable/writable device for a person editor and refuses even a directly invoked click handler', async () => {
    allowed = false; mount()
    expect(trigger().props.disabled).toBe(true)
    await trigger().props.onClick(); await flush()
    expect(state.provider.query).not.toHaveBeenCalled(); expect(dialog()).toBeUndefined()
  })
  it('allows the asset role to open and save the current version', async () => {
    mount(); expect(trigger().props.disabled).toBe(false)
    await trigger().props.onClick(); await flush(); expect(dialog()).toBeTruthy()
    state.editor.emit('save', { name: 'Edited QA asset' }); await flush()
    expect(state.provider.execute).toHaveBeenCalledWith('devices.update', expect.objectContaining({ id: 'qa-device', siteId: 'site-1', expectedVersion: 3, data: { name: 'Edited QA asset' } }), expect.any(Object))
    expect(dialog()).toBeUndefined()
  })
  it('closes an already open form on a refreshed permission revocation and refuses its stale save event', async () => {
    mount(); await trigger().props.onClick(); await flush(); const oldEditor = state.editor
    allowed = false; emit('revision'); oldEditor.emit('save', { name: 'must not save' }); await flush()
    expect(trigger().props.disabled).toBe(true); expect(dialog()).toBeUndefined(); expect(state.store.leaveGuard).toBeNull()
    expect(state.provider.execute).not.toHaveBeenCalled()
  })
  it('does not reopen after a late options response from the old authorization', async () => {
    let resolve; state.provider.query.mockReturnValue(new Promise(done => { resolve = done }))
    mount(); const pending = trigger().props.onClick()
    allowed = false; emit('authorization'); resolve({ data: { availability: 'AVAILABLE' } }); await pending; await flush()
    expect(dialog()).toBeUndefined(); expect(trigger().props.disabled).toBe(true)
  })
  it('preserves lifecycle read-only and closes when the selected site loses permission', async () => {
    props.disabled = true; mount(); await trigger().props.onClick()
    expect(state.provider.query).not.toHaveBeenCalled()
    props.disabled = false; await flush(); await trigger().props.onClick(); await flush()
    state.store.siteId = 'site-2'; await flush()
    expect(dialog()).toBeUndefined(); expect(trigger().props.disabled).toBe(true)
  })
  it('keeps a genuine backend403 visible and never reports save success', async () => {
    state.provider.execute.mockRejectedValue(Object.assign(new Error('当前身份无此操作权限'), { code: 403 }))
    mount(); await trigger().props.onClick(); await flush(); state.editor.emit('save', { name: 'denied' }); await flush()
    expect(dialog()).toBeTruthy(); expect(state.editor.props.error.code).toBe(403)
    expect(find(root, node => node.props?.class === 'notice')).toBeUndefined()
  })
})
