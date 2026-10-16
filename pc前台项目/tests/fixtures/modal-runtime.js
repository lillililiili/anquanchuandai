import { ref } from 'vue'
import { createStore } from '../../src/mock/data.js'
export const tick = ref(0)
export const db = createStore(null)
export const failSave = ref(false)
db.setRemoteCommit(() => { if (failSave.value) throw Error('隔离验收：模拟保存失败') })
db.subscribe(() => { tick.value++ })
