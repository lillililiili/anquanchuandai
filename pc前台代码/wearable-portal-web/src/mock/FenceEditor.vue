<script setup>
import { ref, computed, watch, nextTick } from 'vue'
import { ElMessageBox, ElMessage } from 'element-plus'
import { command, read } from '@spatial-actions'
import { normalizeRing } from '@/utils/fence-geometry'
import { validateFenceDraft } from '@/utils/fence-draft'
import { useLocalEditor } from './useLocalEditor'
import FenceCanvas from './FenceCanvas.vue'
import './spatial-editor.scss'
const props = defineProps({ siteId: String, item: Object, available: Boolean })
const emit = defineEmits(['saved'])
const draft = ref({ nodes: [] }), undo = ref([]), mode = ref('draw'), versions = ref([]), historyOpen = ref(false), lastId = ref('')
const form = ref(), fieldErrors = ref({})
const { user, open, dirty, busy, error, clear, close, run } = useLocalEditor(() => { draft.value = { nodes: [] }; undo.value = []; versions.value = []; historyOpen.value = false })
const allowed = computed(() => props.available && user.roles.includes('owner'))
watch(() => props.siteId, () => { lastId.value = '' })
function start() {
  clear(); fieldErrors.value = {}; draft.value = { name: '', nodes: [], ruleType: '', appliesTo: '' }; mode.value = 'draw'; open.value = true
}
function nodes(value) { undo.value.push(draft.value.nodes.map(p => [...p])); draft.value.nodes = value; dirty.value = true; error.value = ''; mode.value = 'draw' }
function fieldChanged(field) { dirty.value = true; delete fieldErrors.value[field]; error.value = '' }
function undoNodes() { if (!undo.value.length) return; draft.value.nodes = undo.value.pop(); mode.value = 'draw'; dirty.value = true; error.value = '' }
function finish() { try { normalizeRing(draft.value.nodes); mode.value = 'done'; error.value = '' } catch (e) { error.value = e.message } }
async function save() {
  if (busy.value) return
  if (!allowed.value) { error.value = '当前账号或厂站无新增围栏权限'; return }
  const validation = validateFenceDraft(draft.value)
  fieldErrors.value = validation.fields
  if (!validation.valid) {
    error.value = [...Object.values(validation.fields), validation.geometryError].filter(Boolean).join('；')
    ElMessage.warning(error.value)
    await nextTick()
    const target = form.value?.querySelector('[aria-invalid="true"]') || form.value?.querySelector('[role="alert"]')
    target?.focus()
    return
  }
  await run(async signal => {
    mode.value = 'done'
    const result = await command('fence-save', { siteId: props.siteId, ...draft.value, name: draft.value.name.trim(), nodes: undefined, ring: validation.ring, operationId: crypto.randomUUID() }, signal)
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
  <section class="local-toolbar" aria-label="本地围栏操作"><p>前端本地围栏 · 只保存在页面内存 · 不判定真实违规</p><div class="s2-actions"><el-button :disabled="!allowed || busy" @click="start()">新增围栏</el-button><el-button :disabled="!allowed || !item || busy" @click="action('toggle')">{{ item?.status === 'ENABLED' ? '停用围栏' : '启用围栏' }}</el-button><el-button :disabled="!allowed || !item || busy" @click="action('delete')">删除围栏</el-button><el-button :disabled="!available || (!item && !lastId) || busy" @click="history">历史版本</el-button></div><small v-if="!allowed">仅负责人在授权厂站可修改，其他身份只读。</small><p v-if="error && !open" role="alert">{{ error }}</p></section>
  <el-dialog :model-value="open" title="新增围栏" destroy-on-close width="min(950px, 94vw)" append-to-body :close-on-click-modal="false" :before-close="close">
    <form ref="form" novalidate class="local-editor" @submit.prevent="save"><div class="local-fields"><label>围栏名称<input v-model="draft.name" :aria-invalid="!!fieldErrors.name" :aria-describedby="fieldErrors.name ? 'fence-name-error' : undefined" maxlength="100" required :disabled="busy" @input="fieldChanged('name')" /><small v-if="fieldErrors.name" id="fence-name-error" class="fence-field-error">{{ fieldErrors.name }}</small></label><label>规则<select aria-label="规则" v-model="draft.ruleType" :aria-invalid="!!fieldErrors.ruleType" :aria-describedby="fieldErrors.ruleType ? 'fence-ruleType-error' : undefined" required :disabled="busy" @change="fieldChanged('ruleType')"><option value="">请选择规则</option><option value="DENY_ENTRY">禁入</option><option value="DENY_EXIT">禁出</option></select><small v-if="fieldErrors.ruleType" id="fence-ruleType-error" class="fence-field-error">{{ fieldErrors.ruleType }}</small></label><label>适用对象<select aria-label="适用对象" v-model="draft.appliesTo" :aria-invalid="!!fieldErrors.appliesTo" :aria-describedby="fieldErrors.appliesTo ? 'fence-appliesTo-error' : undefined" required :disabled="busy" @change="fieldChanged('appliesTo')"><option value="">请选择对象</option><option value="ALL">全部装备</option><option value="HELMET">安全帽</option><option value="BELT">安全带</option><option value="WATCH">手表</option></select><small v-if="fieldErrors.appliesTo" id="fence-appliesTo-error" class="fence-field-error">{{ fieldErrors.appliesTo }}</small></label></div>
      <div class="s2-actions"><el-button :disabled="busy" :type="mode === 'draw' ? 'primary' : ''" @click="mode = 'draw'">绘制区域</el-button><el-button :disabled="busy || draft.nodes.length < 3 || mode === 'done'" @click="finish">完成绘制</el-button><el-button :disabled="!undo.length || busy" @click="undoNodes">撤销上一步</el-button><el-button :disabled="busy || !draft.nodes.length" @click="nodes([]); mode = 'draw'">清空重画</el-button><span>已绘制 {{ draft.nodes.length }} 个顶点</span></div>
      <FenceCanvas v-if="open" :nodes="draft.nodes || []" :mode="busy ? '' : mode" @change="nodes" />
      <p>在地图上依次单击至少三个不同位置，点击“保存围栏”将自动校验并闭合区域，也可先点击“完成绘制”预览。可拖动地图和缩放；新增范围不自动判定真实违规。</p>

      <p v-if="error" role="alert" class="s2-error" tabindex="-1">{{ error }}</p><div class="s2-actions"><el-button :disabled="busy" @click="close">取消新增</el-button><el-button native-type="submit" type="primary" :loading="busy" :disabled="!allowed || busy">保存围栏</el-button></div>
    </form>
  </el-dialog>
  <el-dialog v-model="historyOpen" title="围栏版本历史（只读）" width="min(720px, 94vw)" append-to-body><ol class="local-versions"><li v-for="v in versions" :key="v.version"><strong>版本 {{ v.version }} · {{ v.name }}</strong><p>{{ v.action }} · {{ v.status }} · {{ v.recordedAt || '种子快照，操作时间未知' }}</p><p>{{ v.rule }} · {{ v.ring?.length - 1 }} 个节点</p><details><summary>查看该版本坐标</summary><pre>{{ JSON.stringify(v.ring, null, 2) }}</pre></details></li></ol></el-dialog>
</template>
