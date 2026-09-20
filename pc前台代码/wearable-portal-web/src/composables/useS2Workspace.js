import { computed, reactive, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useContextStore } from '@/store/context'
import { usePortalQuery } from './usePortalQuery'
import { s2Query } from '@/utils/spatial-contract'
import { useBusinessRevision } from './useBusinessRevision'
export function useS2Workspace(kind, fetcher, detailFetcher) {
  const route = useRoute(), router = useRouter(), context = useContextStore()
  const list = reactive(usePortalQuery()), detail = reactive(usePortalQuery())
  const query = computed(() => s2Query(kind, route.query))
  const siteId = computed(() => query.value.siteId || context.selectedSiteId)
  const availableSite = computed(() => context.state === 'READY' && context.data?.sites.some(s => s.siteId === siteId.value))
  watch([siteId, availableSite], () => { if (availableSite.value) context.select(siteId.value) }, { immediate: true })
  const params = computed(() => { const q = { ...query.value, siteId: siteId.value }; delete q.selectedId; return q })
  const selectedId = computed(() => query.value.selectedId || '')
  const selected = computed(() => list.data?.items?.find(i => i.id === selectedId.value))
  async function reload() {
    detail.clear()
    if (!availableSite.value) { list.clear(); return }
    if (kind === 'tracks' && (!params.value.deviceId || !params.value.from)) { list.clear(); return }
    await list.run(signal => fetcher(params.value, signal))
    if (kind !== 'tracks' && list.data?.state === 'AVAILABLE' && list.data.total > 0 && !list.data.items.length && Number(query.value.pageNum || 1) > 1) page(Math.ceil(list.data.total / Number(query.value.pageSize || 20)))
  }
  watch([() => JSON.stringify(params.value), () => context.state], reload, { immediate: true })
  useBusinessRevision([kind], reload)
  watch([selectedId, () => list.data], () => {
    detail.clear()
    if (selectedId.value && availableSite.value && list.data?.state === 'AVAILABLE' && detailFetcher) detail.run(signal => detailFetcher(selectedId.value, siteId.value, signal))
  })
  function navigate(q, replace = false) {
    return router[replace ? 'replace' : 'push']({ path: kind === 'materials' ? '/materials' : '/location', query: { ...(kind === 'materials' ? {} : { tab: kind }), ...s2Query(kind, q) } })
  }
  function search(filters = {}) { return navigate({ siteId: siteId.value, pageSize: query.value.pageSize, ...filters }) }
  function select(id) { return navigate({ ...query.value, siteId: siteId.value, selectedId: id }, true) }
  function page(n) { return navigate({ ...query.value, siteId: siteId.value, selectedId: undefined, pageNum: String(n) }) }
  return { route, router, context, list, detail, query, params, siteId, availableSite, selectedId, selected, reload, search, select, page }
}
