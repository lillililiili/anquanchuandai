import { ref, onScopeDispose } from 'vue'
export function usePortalQuery() {
  const data = ref(null), state = ref('IDLE'), error = ref(null), asOf = ref(null)
  let revision = 0, controller
  function clear() { revision++; controller?.abort(); data.value = null; error.value = null; asOf.value = null; state.value = 'IDLE' }
  async function run(fetcher) {
    clear()
    const current = revision
    controller = new AbortController()
    state.value = 'LOADING'
    try {
      const result = await fetcher(controller.signal)
      if (current !== revision) return
      data.value = result.data
      asOf.value = result.asOf
      state.value = 'READY'
    } catch (e) {
      if (current !== revision || e.code === 'ERR_CANCELED') return
      error.value = e
      state.value = e.code === 403 ? 'FORBIDDEN' : 'ERROR'
    }
  }
  onScopeDispose(clear)
  return { data, state, error, asOf, run, clear }
}

