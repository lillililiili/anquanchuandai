// Production entry point is closed. No URL is read from metadata, route, storage or environment.
export const closedMediaProvider = Object.freeze({ async acquire() { return { state: 'NOT_INTEGRATED', reason: '真实媒体访问未开放' } } })
