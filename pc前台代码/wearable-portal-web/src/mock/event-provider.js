import request from './request.js'
export const enabled = true
export const editor = (params, signal) => request.get('/mock-events/editor', { params, signal })
export async function command(action, input, signal) {
  const result = await request.post('/mock-events/' + action, input, { signal })
  return result
}
