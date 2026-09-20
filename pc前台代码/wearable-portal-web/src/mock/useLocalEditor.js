import { ref, watch, onBeforeUnmount } from 'vue'
import { onBeforeRouteLeave, onBeforeRouteUpdate } from 'vue-router'
import { ElMessageBox } from 'element-plus'
import 'element-plus/es/components/message-box/style/css'
import { useUserStore } from '@/store/user'
import { useContextStore } from '@/store/context'
export function useLocalEditor(clearData) {
  const user = useUserStore(), context = useContextStore()
  const open = ref(false), dirty = ref(false), busy = ref(false), error = ref('')
  let controller = new AbortController()
  function clear() { controller.abort(); controller = new AbortController(); open.value = dirty.value = busy.value = false; error.value = ''; clearData?.() }
  async function leave() {
    if (!user.token || !open.value || !dirty.value) return true
    if (busy.value) return false
    try { await ElMessageBox.confirm('离开将丢弃尚未保存的内容；已保存的本地记录不会回滚。', '放弃未保存内容？', { confirmButtonText: '放弃编辑', cancelButtonText: '继续编辑', closeOnHashChange: false }); return true } catch { return false }
  }
  async function close() { if (!busy.value && await leave()) clear() }
  onBeforeRouteLeave(leave); onBeforeRouteUpdate(leave)
  watch(() => [user.token, context.selectedSiteId], clear)
  const unload = e => { if (dirty.value) { e.preventDefault(); e.returnValue = '' } }
  window.addEventListener('beforeunload', unload)
  onBeforeUnmount(() => { clear(); window.removeEventListener('beforeunload', unload) })
  async function run(fn) {
    if (busy.value) return
    const signal = controller.signal
    busy.value = true; error.value = ''
    try { return await fn(signal) } catch (e) { if (!signal.aborted && e.code !== 'ERR_CANCELED') error.value = e.message + (e.requestId ? `（${e.requestId}）` : '') }
    finally { if (!signal.aborted) busy.value = false }
  }
  return { user, context, open, dirty, busy, error, clear, close, run }
}
