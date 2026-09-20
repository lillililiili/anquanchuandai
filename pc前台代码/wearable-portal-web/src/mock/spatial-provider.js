import request from './request.js'
import { useWorkspaceStore } from '@/store/workspace'
export const enabled = true
export const read = (action, params, signal) => request.get('/mock-spatial/' + action, { params, signal })
export async function command(action, data, signal) {
  const response = await request.post('/mock-spatial/' + action, data, { signal })
  if (!response.data.replayed) useWorkspaceStore().invalidate(response.data.changedEntities)
  return response
}
