import { ref } from 'vue';
import { createStore } from '../../src/mock/data.js';
import { fixtureState, SCENARIOS } from './person-device-data.mjs';
export { SCENARIOS };
export const tick = ref(0);
export const connection = ref({ status: 'online', message: '隔离验收：内存数据，无后端连接' });
export const scenario = ref(new URLSearchParams(location.search).get('scenario') || 'belt');
export const blockedOperations = ref([]);
export const db = createStore(null, { demoMode: false });
db.subscribe(() => tick.value++);
export function selectScenario(value) { scenario.value = value; db.replaceRemote(fixtureState(value)); }
selectScenario(scenario.value);
export function blocked(message = '隔离验收：设备服务不可用，未发送实际请求') {
  blockedOperations.value = [...blockedOperations.value.slice(-5), message];
  throw Error(message);
}
db.setRemoteCommit(() => blocked('隔离验收：业务写入被阻止，不会保存到数据库'));
db.setVoice(() => blocked());
for (const name of ['claim','verify','observe','addEventPhoto','sos']) db[name] = () => blocked('隔离验收：处置写入被阻止，未修改实际事件');
export const refreshSnapshot = async () => true;
export const guardianReady = Promise.resolve(true);
export const locationApi = { history: async () => ({ points: [], unverified: 0, truncated: false }) };
