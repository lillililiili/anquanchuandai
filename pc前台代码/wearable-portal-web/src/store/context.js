import { defineStore } from 'pinia'
import { ref } from 'vue'
import { getContext } from '@/api/portal'
import { useWorkspaceStore } from './workspace'
export const useContextStore = defineStore('portal-context', () => {
  const data = ref(null), state = ref('IDLE'), error = ref(null), selectedSiteId = ref('')
  let controller, pending, revision = 0
  function reset() {
    useWorkspaceStore().reset()
    revision++; controller?.abort(); pending = null
    data.value = null; state.value = 'IDLE'; error.value = null; selectedSiteId.value = ''
  }
  async function load(force = false) {
    if (!force && state.value === 'READY') return
    if (!force && pending) return pending
    controller?.abort()
    const current = ++revision
    controller = new AbortController()
    state.value = 'LOADING'; error.value = null
    const task = getContext(controller.signal).then(result => {
      if (current !== revision) return
      data.value = result.data
      if (!data.value.sites.some(s => s.siteId === selectedSiteId.value)) selectedSiteId.value = data.value.selectedSiteId || ''
      state.value = 'READY'
    }).catch(e => {
      if (current !== revision || e.code === 'ERR_CANCELED') return
      error.value = e; data.value = null; selectedSiteId.value = ''; state.value = 'ERROR'
    }).finally(() => { if (pending === task) pending = null })
    pending = task
    return task
  }
  function select(id) { if (data.value?.sites.some(s => s.siteId === id) && selectedSiteId.value !== id) { useWorkspaceStore().clear(); selectedSiteId.value = id } }
  return { data, state, error, selectedSiteId, reset, load, select }
})
