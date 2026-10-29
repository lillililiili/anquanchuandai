import { onBeforeUnmount, ref } from 'vue'
import { getAdminProvider } from '@admin-provider'
export function useQuery() {
  const data = ref(null), error = ref(null), loading = ref(false), refreshing = ref(false)
  let controller, version = 0, dataKey = null
  function cancel() { version++; controller?.abort(); loading.value = false; refreshing.value = false; data.value = null; dataKey = null; error.value = null }
  async function run(kind, input, { background = false } = {}) {
    const key = JSON.stringify([kind, input])
    // Keep the existing subtree mounted only for the same authorized query.
    // New devices, sites or pages still clear their previous result immediately.
    const retain = background && data.value != null && dataKey === key
    const id = ++version
    controller?.abort()
    controller = new AbortController()
    if (!retain) { data.value = null; dataKey = null }
    error.value = null
    loading.value = !retain
    refreshing.value = retain
    try {
      const result = await getAdminProvider().query(kind, input, { signal: controller.signal })
      if (id === version) { data.value = result.data; dataKey = key }
    } catch (e) {
      if (id === version && e.name !== 'AbortError') {
        data.value = null; dataKey = null
        error.value = e
        if (e.code === 401) getAdminProvider().invalidate()
      }
    } finally { if (id === version) { loading.value = false; refreshing.value = false } }
  }
  onBeforeUnmount(cancel)
  return { data, error, loading, refreshing, run, cancel }
}
