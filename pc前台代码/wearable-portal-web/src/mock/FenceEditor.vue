<script setup>
import { ref, computed, watch } from 'vue'
import { ElMessageBox, ElMessage } from 'element-plus'
import { command, read } from '@spatial-actions'
import { normalizeRing } from '@/utils/fence-geometry'
import { useLocalEditor } from './useLocalEditor'
import FenceCanvas from './FenceCanvas.vue'
import './spatial-editor.scss'
const props = defineProps({ siteId: String, item: Object, available: Boolean })
const emit = defineEmits(['saved'])
const draft = ref({ nodes: [] }), undo = ref([]), mode = ref('draw'), versions = ref([]), historyOpen = ref(false), lastId = ref('')
const { user, open, dirty, busy, error, clear, close, run } = useLocalEditor(() => { draft.value = { nodes: [] }; undo.value = []; versions.value = []; historyOpen.value = false })
const allowed = computed(() => props.available && user.roles.includes('owner'))
watch(() => props.siteId, () => { lastId.value = '' })
function start(item) {
  clear(); draft.value = { id: item?.id, expectedVersion: item?.version, name: item?.name || '', nodes: item?.ring?.slice(0, -1).map(p => [...p]) || [], ruleType: item?.ruleType || '', appliesTo: item?.appliesTo || '' }; mode.value = item ? 'edit' : 'draw'; open.value = true
}
function nodes(value) { undo.value.push(draft.value.nodes.map(p => [...p])); draft.value.nodes = value; dirty.value = true }
function editNode(index, axis, event) { const value = draft.value.nodes.map(p => [...p]); value[index][axis] = event.target.value === '' ? NaN : Number(event.target.value); nodes(value) }
async function save() {
  await run(async signal => {
    const ring = normalizeRing(draft.value.nodes)
    const result = await command('fence-save', { siteId: props.siteId, ...draft.value, nodes: undefined, ring, operationId: crypto.randomUUID() }, signal)
    if (signal.aborted) return
    lastId.value = result.data.id; dirty.value = false; clear(); emit('saved'); ElMessage.success('围栏已保存到页面内存，已生成版本')
  })
}
async function action(type) {
  if (!props.item || !allowed.value) return
  const target = { siteId: props.siteId, id: props.item.id, expectedVersion: props.item.version }, token = user.token
  if (type === 'delete') { try { await ElMessageBox.confirm('仅删除当前本地围栏，版本历史保留；不会下发设备命令。', '删除围栏？', { confirmButtonText: '确认删除', cancelButtonText: '取消' }) } catch { return } }
  if (props.siteId !== target.siteId || user.token !== token) return
  await run(async signal => { const result = await command('fence-' + type, { ...target, operationId: crypto.randomUUID() }, signal); if (!signal.aborted) { lastId.value = result.data.id; emit('saved'); ElMessage.success('操作已本地暂存，历史版本保留') } })
}
async function history() { await run(async signal => { const r = await read('versions', { siteId: props.siteId, id: props.item?.id || lastId.value }, signal); if (!signal.aborted) { versions.value = r.data; historyOpen.value = true } }) }
</script>
<template>
  <section class="local-toolbar" aria-label="本地围栏操作"><p>前端本地围栏 · 只保存在页面内存 · 不判定真实违规</p><div class="s2-actions"><el-button :disabled="!allowed || busy" @click="start()">新建围栏</el-button><el-button :disabled="!allowed || !item || busy" @click="start(item)">编辑围栏</el-button><el-button :disabled="!allowed || !item || busy" @click="action('toggle')">{{ item?.status === 'ENABLED' ? '停用围栏' : '启用围栏' }}</el-button><el-button :disabled="!allowed || !item || busy" @click="action('delete')">删除围栏</el-button><el-button :disabled="!available || (!item && !lastId) || busy" @click="history">历史版本</el-button></div><small v-if="!allowed">仅负责人在授权厂站可修改，其他身份只读。</small><p v-if="error && !open" role="alert">{{ error }}</p></section>
  <el-dialog :model-value="open" title="本地围栏编辑" width="min(950px, 94vw)" append-to-body :close-on-click-modal="false" :before-close="close">
    <form class="local-editor" @submit.prevent="save"><div class="local-fields"><label>围栏名称<input v-model="draft.name" maxlength="100" required :disabled="busy" @input="dirty = true" /></label><label>规则<select aria-label="规则" v-model="draft.ruleType" required :disabled="busy" @change="dirty = true"><option value="">请选择规则</option><option value="DENY_ENTRY">禁入</option><option value="DENY_EXIT">禁出</option></select></label><label>适用对象<select aria-label="适用对象" v-model="draft.appliesTo" required :disabled="busy" @change="dirty = true"><option value="">请选择对象</option><option value="ALL">全部装备</option><option value="HELMET">安全帽</option><option value="BELT">安全带</option><option value="WATCH">手表</option></select></label></div>
      <div class="s2-actions"><el-button :disabled="busy" :type="mode === 'draw' ? 'primary' : ''" @click="mode = 'draw'">绘制区域</el-button><el-button :disabled="busy" :type="mode === 'edit' ? 'primary' : ''" @click="mode = 'edit'">编辑节点</el-button><el-button :disabled="!undo.length || busy" @click="draft.nodes = undo.pop(); dirty = true">撤销</el-button><el-button :disabled="busy || draft.nodes.length >= 500" @click="nodes([...draft.nodes, [0, 0]])">添加坐标节点</el-button></div>
      <FenceCanvas :nodes="draft.nodes || []" :mode="busy ? '' : mode" @change="nodes" />
      <p>仅简单闭合多边形，保存时自动闭合。初始新增节点0,0仅为输入值，请按预置需要编辑，不代表厂区位置。</p>
      <div class="node-table"><div v-for="(point, i) in draft.nodes" :key="i" class="local-fields"><span>{{ i + 1 }}</span><label>经度 {{ i + 1 }}<input type="number" step="any" :value="point[0]" :disabled="busy" @change="editNode(i, 0, $event)" /></label><label>纬度 {{ i + 1 }}<input type="number" step="any" :value="point[1]" :disabled="busy" @change="editNode(i, 1, $event)" /></label><el-button :disabled="busy" :aria-label="'删除节点 ' + (i + 1)" @click="nodes(draft.nodes.filter((_, index) => index !== i))">删除节点</el-button></div></div>
      <p v-if="error" role="alert" class="s2-error">{{ error }}</p><div class="s2-actions"><el-button :disabled="busy" @click="close">取消编辑</el-button><el-button native-type="submit" type="primary" :loading="busy" :disabled="!allowed || busy">保存围栏</el-button></div>
    </form>
  </el-dialog>
  <el-dialog v-model="historyOpen" title="围栏版本历史（只读）" width="min(720px, 94vw)" append-to-body><ol class="local-versions"><li v-for="v in versions" :key="v.version"><strong>版本 {{ v.version }} · {{ v.name }}</strong><p>{{ v.action }} · {{ v.status }} · {{ v.recordedAt || '种子快照，操作时间未知' }}</p><p>{{ v.rule }} · {{ v.ring?.length - 1 }} 个节点</p><details><summary>查看该版本坐标</summary><pre>{{ JSON.stringify(v.ring, null, 2) }}</pre></details></li></ol></el-dialog>
</template>
