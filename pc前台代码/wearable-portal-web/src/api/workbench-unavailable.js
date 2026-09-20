// No agreed real endpoint: never guess one or fall back to mock data.
export const getWorkbench = async siteId => ({ data: { siteId, source: null, ...Object.fromEntries(['duty', 'equipment', 'open', 'mine', 'unknown'].map(k => [k, { state: 'NOT_INTEGRATED', data: null }])) } })
