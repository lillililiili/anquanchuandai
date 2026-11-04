import { ref } from 'vue';
import { createStore } from '../../src/mock/data.js';
import { fixtureState, SCENARIOS } from './person-device-data.mjs';
import { allowFixtureFenceCommit } from './person-device-writes.mjs';
import { session } from './person-device-session.js';
export { SCENARIOS };
export const tick = ref(0);
export const connection = ref({ status: 'online', message: '隔离验收：内存数据，无后端连接' });
export const scenario = ref(new URLSearchParams(location.search).get('scenario') || 'belt');
export const blockedOperations = ref([]);
export const memoryWrites = ref([]);
export const db = createStore(null, { demoMode: false });
db.subscribe(() => tick.value++);
export function selectScenario(value) {
  scenario.value = value; session.fenceDraft = null; session.fence = ''; session.fenceMode = 'select'; session.fenceUndo = [];
  memoryWrites.value = []; blockedOperations.value = []; db.replaceRemote(fixtureState(value));
  if (value === 'fences') { session.filters.fences = {}; session.fence = db.state.fences[0].id; session.fenceDraft = structuredClone(db.state.fences[0]); }
  if (value === 'works_many') { session.filters.works = {}; session.work = 'QA-WORK'; }
}
selectScenario(scenario.value);
export function blocked(message = '隔离验收：设备服务不可用，未发送实际请求') {
  blockedOperations.value = [...blockedOperations.value.slice(-5), message];
  throw Error(message);
}
db.setRemoteCommit(next => {
  try {
    const label = allowFixtureFenceCommit(db.state, next, scenario.value);
    memoryWrites.value = [...memoryWrites.value.slice(-5), label + ' · 仅当前页面内存，刷新即重置'];
  } catch (error) { blocked(error.message); }
});
db.setVoice(() => blocked());
for (const name of ['claim','verify','observe','addEventPhoto','sos']) db[name] = () => blocked('隔离验收：处置写入被阻止，未修改实际事件');
export const refreshSnapshot = async () => true;
export const guardianReady = Promise.resolve(true);
export const locationApi = { history: async () => ({ points: [], unverified: 0, truncated: false }) };
