import { describe, expect, it } from 'vitest'
import { createSSRApp, h } from 'vue'
import { renderToString } from 'vue/server-renderer'
import MasterEditor from './components/MasterEditor.vue'
import { OPERATIONS } from './access'

async function checkedPermissions(operations, builtin) {
  const app = createSSRApp(MasterEditor, {
    entity: 'roles', siteId: 'site-1', isSystem: true,
    record: { id: 'role-1', name: '角色', builtin, version: 1, grants: [{ operations, siteIds: ['site-1'] }] },
    options: { sites: [{ id: 'site-1', name: '测试厂区' }] }
  })
  app.component('UiSelect', { setup: (_props, { slots }) => () => h('select', slots.default?.()) })
  const html = await renderToString(app)
  return [...html.matchAll(/<input\b[^>]*>/g)].map(match => match[0])
    .filter(input => input.includes('type="checkbox"') && /\schecked(?:\s|>|=)/.test(input))
    .map(input => input.match(/value="([^"]+)"/)[1])
}

describe('unified role permission editor', () => {
  it.each([true, false])('shows explicit permissions identically regardless of role origin (%s)', async builtin => {
    expect(await checkedPermissions(['people:read', 'assets:write'], builtin)).toEqual(['people:read', 'assets:write'])
  })
  it('expands legacy wildcard permissions into editable checked choices', async () => {
    const visible = OPERATIONS.filter(item => !item.startsWith('integrations:') && !item.startsWith('duty:') && item !== 'groups:write')
    expect(await checkedPermissions(['*'], true)).toEqual(visible)
  })
})
