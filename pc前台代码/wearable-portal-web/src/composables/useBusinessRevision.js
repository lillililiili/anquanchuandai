import { watch } from 'vue'
import { useWorkspaceStore } from '@/store/workspace'
export function useBusinessRevision(entities, reload) {
  const workspace = useWorkspaceStore()
  watch(() => workspace.revision, () => { if (entities.some(e => workspace.changedEntities.includes(e))) reload() })
}
