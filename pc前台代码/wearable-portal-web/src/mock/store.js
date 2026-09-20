import { defineStore } from 'pinia'
import { ref } from 'vue'
import { readDataset, saveScenario, resetDataset } from './storage.js'
import { defaultScenario } from './seed.js'
export const useMockStore = defineStore('mock-controls', () => {
  const config = ref(defaultScenario()), baseTime = ref(''), busy = ref(false), error = ref('')
  async function execute(fn) {
    busy.value = true; error.value = ''
    try { const d = await fn(); config.value = d.config; baseTime.value = d.meta.baseTime; return true }
    catch (e) { error.value = e.message; return false }
    finally { busy.value = false }
  }
  return { config, baseTime, busy, error, load: () => execute(readDataset), save: c => execute(() => saveScenario(c)), reset: () => execute(resetDataset) }
})
