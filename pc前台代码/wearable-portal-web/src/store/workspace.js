import { defineStore } from 'pinia'
import { ref } from 'vue'
import { personIdPattern } from '@/utils/portal-route'
export const useWorkspaceStore = defineStore('workspace', () => {
  const selection = ref({}), revision = ref(0), changedEntities = ref([])
  function clear() { selection.value = {} }
  function select(siteId, deviceId) {
    selection.value = personIdPattern.test(siteId || '') && personIdPattern.test(deviceId || '') ? { siteId, deviceId } : {}
  }
  // Reserved for validated future commands, not a second entity store.
  function invalidate(entities) { changedEntities.value = [...new Set(entities)]; revision.value++ }
  function reset() { clear(); changedEntities.value = []; revision.value++ }
  return { selection, revision, changedEntities, select, clear, reset, invalidate }
})
