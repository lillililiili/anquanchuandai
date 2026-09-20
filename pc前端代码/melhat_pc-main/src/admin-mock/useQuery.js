import { onBeforeUnmount, ref } from 'vue'
import { getAdminProvider } from '@admin-provider'
export function useQuery() {
  const data = ref(null), error = ref(null), loading = ref(false)
  let controller, version = 0
  function cancel() { version++; controller?.abort(); loading.value = false; data.value = null; error.value = null }
  async function run(kind, input) {
    cancel()
    const id = version
    controller = new AbortController()
    loading.value = true
    try {
      const result = await getAdminProvider().query(kind, input, { signal: controller.signal })
      if (id === version) data.value = result.data
    } catch (e) {
      if (id === version && e.name !== 'AbortError') {
        error.value = e
        if (e.code === 401) getAdminProvider().invalidate()
      }
    } finally { if (id === version) loading.value = false }
  }
  onBeforeUnmount(cancel)
  return { data, error, loading, run, cancel }
}
