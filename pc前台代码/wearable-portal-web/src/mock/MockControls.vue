<script setup>
import { ref, reactive } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessageBox } from 'element-plus'
import { useContextStore } from '@/store/context'
import { useUserStore } from '@/store/user'
import { useMockStore } from './store'
import { defaultScenario } from './seed'
import { expireSession } from './request'
import './mock.scss'
import SosTrigger from './SosTrigger.vue'
const router = useRouter(), context = useContextStore(), user = useUserStore(), mock = useMockStore()
const open = ref(false), form = reactive(defaultScenario())
async function show() { open.value = true; if (await mock.load()) Object.assign(form, mock.config) }
async function apply(reset = false) {
  if (await mock.save(reset ? defaultScenario() : { ...form })) { Object.assign(form, mock.config); open.value = false; await context.load(true) }
}
async function reset() {
  try { await ElMessageBox.confirm('将恢复当前页面的内存预置数据并退出当前身份。不会清理后端、正式账号或独立数据库环境。', '确认重置本地数据', { type: 'warning', confirmButtonText: '确认恢复', cancelButtonText: '取消' }) } catch { return }
  if (await mock.reset()) { open.value = false; user.clearSession(); await router.replace('/login') }
}
function expire() { open.value = false; expireSession() }
</script>
<template>
  <button class="mock-badge mock-control-button" aria-label="服务未接入 · 本地工作空间：打开场景控制" title="全部已接入内容为预置数据；点击控制场景" @click="show">服务未接入 · 本地工作空间 · 预置数据</button>
  <el-dialog v-model="open" title="本地场景控制" width="520px" append-to-body :close-on-click-modal="false">
    <p class="mock-explanation">页面中“已接入”均为预置数据；不会访问真实设备、后端或外部系统。场景只影响选择的模块，不修改种子事实。</p>
    <p class="mock-explanation">数据与场景仅保存在内存中：切换菜单继续保留，刷新恢复初始状态。本地身份进入会话单独保留。</p>
    <form class="mock-form" @submit.prevent="apply()">
      <label for="mock-module">目标模块</label><select id="mock-module" v-model="form.module"><option v-for="(name, key) in { dispatch: '调度协同', works: '作业监护', people: '人员', equipment: '装备与领用', vitals: '生命体征', locations: '定位', tracks: '轨迹', fences: '围栏', materials: '资料', video: '视频元数据', events: '事件与核验' }" :key="key" :value="key">{{ name }}</option></select>
      <label for="mock-scenario">查询场景</label><select id="mock-scenario" v-model="form.mode"><option value="normal">正常</option><option value="not-integrated">来源未接入</option><option value="failure">请求失败</option><option value="forbidden">详情或关联分区无权限</option></select>
      <label class="mock-checkbox"><input v-model="form.slowNext" type="checkbox" />该模块下一次查询延迟 3 秒</label>
      <p class="mock-explanation">离线、过期、未知和冲突使用固定样例。空数据请选“空厂站”。源时间以初始化基准为准：{{ mock.baseTime }}；不会按浏览器时间伪造设备上报。</p>
      <p v-if="mock.error" class="form-error" role="alert">{{ mock.error }}</p>
      <div class="mock-actions"><el-button native-type="submit" type="primary" :loading="mock.busy">应用场景</el-button><el-button :disabled="mock.busy" @click="apply(true)">恢复正常场景</el-button><el-button :disabled="mock.busy" @click="expire">本地会话失效</el-button><el-button :disabled="mock.busy" @click="reset">重置本地数据</el-button></div>
    </form>
    <SosTrigger v-if="open" @triggered="open = false" />
  </el-dialog>
</template>
