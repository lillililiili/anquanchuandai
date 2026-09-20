import { computed, ref } from 'vue'
import { defineStore } from 'pinia'
import { ElMessageBox } from 'element-plus'
import request from './request'
import { readDataset, transact } from './storage'
import { dispatchData, closeActiveDispatch } from './dispatch-service'
import { useWorkspaceStore } from '@/store/workspace'
import pinia from '@/store'
import { validateDispatch } from '@/utils/dispatch-contract'
const revision = ref(0)
export const enabled = true
export const useDispatchStore = defineStore('mock-dispatch', () => {
  const data = computed(() => { revision.value; return dispatchData(readDataset()) })
  const active = computed(() => data.value.sessions.find(s => s.state === 'ACTIVE') || null)
  return { data, active }
})
export async function queryDispatch(params, signal) { return validateDispatch((await request.get('/mock-dispatch/query', { params, signal })).data, params) }
export async function commandDispatch(action, body, signal) {
  const result = (await request.post('/mock-dispatch/' + action, body, { signal })).data
  revision.value++; useWorkspaceStore(pinia).invalidate(result.changedEntities)
  return result
}
export function clearDispatchSession() { transact(d => closeActiveDispatch(d, '身份或会话已清理，结束本地协同')); revision.value++ }
export async function beforeDispatchLeave(siteId, logout = false) {
  const active = dispatchData(readDataset()).sessions.find(s => s.state === 'ACTIVE')
  if (!active || !logout && (!siteId || active.siteId === siteId)) return true
  try { await ElMessageBox.confirm('当前有活动本地会话。结束后再切换厂站或退出；关联事件不会完成。', '结束本地会话后离开？', { confirmButtonText: '结束并离开', cancelButtonText: '保持当前会话', type: 'warning' }) } catch { return false }
  // Only end the captured session; never end a newly started replacement.
  const now = dispatchData(readDataset()).sessions.find(s => s.state === 'ACTIVE')
  if (now && now.id !== active.id) return false
  clearDispatchSession(); return true
}
