import { computed, reactive, watch } from 'vue'
import { useRoute } from 'vue-router'
import { useContextStore } from '@/store/context'
import { useUserStore } from '@/store/user'
import { usePortalQuery } from './usePortalQuery'
import { getEvent } from '@/api/events'
import { useBusinessRevision } from '@/composables/useBusinessRevision'
export function useEventWorkspace(selectedId) {
  const route = useRoute(), context = useContextStore(), user = useUserStore()
  const siteId = computed(() => typeof route.query.siteId === 'string' ? route.query.siteId : context.selectedSiteId)
  const availableSite = computed(() => !!user.token && context.state === 'READY' && !!context.data?.sites.some(s => s.siteId === siteId.value))
  const detail = reactive(usePortalQuery())
  function reloadDetail() { if (availableSite.value && selectedId.value) return detail.run(s => getEvent(selectedId.value, siteId.value, s)); detail.clear() }
  watch([siteId, availableSite, selectedId, () => user.token], () => { if (availableSite.value) context.select(siteId.value); reloadDetail() }, { immediate: true })
  useBusinessRevision(['events'], reloadDetail)
  return { route, context, user, siteId, availableSite, detail, reloadDetail }
}
