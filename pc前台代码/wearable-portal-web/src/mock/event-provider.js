import request from './request.js'
export async function command(action, input, signal) {
  return request.post('/mock-events/' + action, input, { signal })
}
