import { createSeed } from './seed.js'

// Shared per page lifetime. Pinia holds UI state; this repository holds mock facts.
// No IndexedDB/localStorage persistence. Reload creates a fresh module instance.
export function createMemoryRepository(seed = createSeed) {
  let dataset
  function transact(update, reset = false) {
    const draft = structuredClone(reset || !dataset ? seed() : dataset)
    // Commit only after a successful synchronous update; return an isolated copy.
    if (update) {
      if (update(draft) === false) return structuredClone(dataset || draft)
      draft.meta.businessRevision = (draft.meta.businessRevision || 0) + 1
    }
    dataset = draft
    return structuredClone(dataset)
  }
  return {
    transact,
    readDataset: () => transact(),
    saveScenario: config => transact(data => { data.config = { ...config } }),
    resetDataset: () => transact(null, true)
  }
}
export const { transact, readDataset, saveScenario, resetDataset } = createMemoryRepository()
