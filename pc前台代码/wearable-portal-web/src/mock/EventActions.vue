<script setup>
import { ref, computed, watch } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { useWorkspaceStore } from '@/store/workspace'
import { useLocalEditor } from './useLocalEditor'
import { editor, command } from './event-provider'
import EvidencePicker from './EvidencePicker.vue'
import { conclusionLabels } from '@/utils/event-contract'
import './spatial-editor.scss'
const props = defineProps({ event: { type: Object, required: true }, siteId: String })
const mode = ref('verification'), form = ref({}), options = ref([]), target = ref(''), version = ref(1), picked = ref(null), workspace = useWorkspaceStore()
const { user, open, dirty, busy, error, clear, close, run } = useLocalEditor(() => { form.value = {}; picked.value = null; target.value = '' })
watch(() => props.event.eventId, clear)
const writable = computed(() => ['owner', 'verifier'].some(r => user.roles.includes(r)))
const responsible = computed(() => props.event.ownerUserId === user.user?.userId)
const active = computed(() => ['PROCESSING', 'AWAITING_VERIFICATION'].includes(props.event.phase))
async function start(next) {
  clear(); mode.value = next; open.value = true
  await run(async signal => {
    const result = await editor({ siteId: props.siteId, eventId: props.event.eventId, mode: next }, signal)
    if (signal.aborted) return
    version.value = result.data.version; options.value = result.data.assignees
    const draft = result.data.draft
    form.value = { conclusion: draft?.conclusion || '', scene: draft?.scene || '', measures: draft?.measures || '', evidence: (draft?.evidence?.data || []).map(e => ({ id: e.id, version: e.version, name: e.name })) }
  })
}
function addEvidence() { if (picked.value && !form.value.evidence.some(e => e.id === picked.value.id)) { form.value.evidence.push({ id: picked.value.id, version: picked.value.version, name: picked.value.name }); dirty.value = true } }
async function execute(action, extra = {}) {
  const input = { siteId: props.siteId, eventId: props.event.eventId, expectedVersion: open.value ? version.value : props.event.version || 1, operationId: crypto.randomUUID(), ...extra }, token = user.token
  if (['complete', 'submit', 'transfer'].includes(action)) {
    try { await ElMessageBox.confirm(action === 'submit' ? '提交后生成不可修改的核验版本，不会自动完成跟进。' : action === 'complete' ? '确认完成本地跟进？不代表原系统结案，本期不支持重开。' : '确认转交给所选处置人？', '确认本地操作', { confirmButtonText: '确认操作', cancelButtonText: '取消', closeOnHashChange: false }) } catch { return }
    if (user.token !== token || props.event.eventId !== input.eventId || props.siteId !== input.siteId) return
  }
  await run(async signal => {
    const result = await command(action, input, signal)
    if (signal.aborted) return
    dirty.value = false; clear(); ElMessage.success('操作已本地暂存；刷新恢复种子，未发送外部系统')
    if (!result.data.replayed) workspace.invalidate(result.data.changedEntities)
  })
}
</script>
<template>
  <section class="local-toolbar" aria-label="本地事件处置">
    <strong>事件处置 · 前端内存预置</strong><p>草稿不改变阶段；提交不自动完成；回执不代表结案。</p>
    <div class="s2-actions"><el-button :disabled="!writable || event.phase !== 'UNCLAIMED' || busy" @click="execute('claim')">认领事件</el-button><el-button :disabled="!writable || !responsible || !active || busy" @click="start('transfer')">转交事件</el-button><el-button :disabled="!writable || !responsible || event.phase !== 'PROCESSING' || busy" @click="execute('verify')">转现场核验</el-button><el-button :disabled="!writable || event.phase !== 'AWAITING_VERIFICATION' || busy" @click="start('verification')">编写核验 / 我的草稿</el-button><el-button :disabled="!writable || !responsible || event.phase !== 'AWAITING_VERIFICATION' || busy" @click="execute('complete')">完成本地跟进</el-button><el-button :disabled="!writable || !responsible || busy" @click="start('receipt')">本地回执</el-button></div>
    <p v-if="!writable">只读身份不能处置事件或编辑核验。</p><p v-else-if="event.phase === 'LOCAL_COMPLETED'">本地跟进已完成；不提供重开、转交或再次提交。</p><p v-else>认领仅限待认领；转交、转核验和完成仅限当前负责人。核验仅在待现场核验阶段开放，未知阶段须先核实。</p><p v-if="error && !open" role="alert">{{ error }}</p>
  </section>
  <el-dialog :model-value="open" :title="mode === 'verification' ? '本地核验编辑' : mode === 'transfer' ? '本地事件转交' : '本地外部回执（不联网）'" width="min(760px, 94vw)" append-to-body :close-on-click-modal="false" :before-close="close">
    <div class="local-editor event-editor">
      <template v-if="mode === 'verification'"><label>核验结论<select aria-label="核验结论" v-model="form.conclusion" :disabled="busy" @change="dirty = true"><option value="">请选择结论</option><option v-for="(label, key) in conclusionLabels" :key="key" :value="key">{{ label }}</option></select></label><label>现场情况<textarea v-model="form.scene" rows="4" maxlength="4000" :disabled="busy" @input="dirty = true" /></label><label>后续措施<textarea v-model="form.measures" rows="3" maxlength="4000" :disabled="busy" @input="dirty = true" /></label><p>提交需结论和现场情况；“需现场处理”必须填写措施。“无法确认”保持待现场核验。</p><EvidencePicker v-if="form.evidence" :site-id="siteId" @select="picked = $event" /><el-button :disabled="busy || !picked || form.evidence?.length >= 20" @click="addEvidence">加入核验证据</el-button><p v-if="!form.evidence?.length">无附件；允许明确无影像核验，不虚构证据。</p><ul><li v-for="e in form.evidence" :key="e.id">{{ e.name }} · 版本{{ e.version }} <el-button :disabled="busy" @click="form.evidence = form.evidence.filter(i => i.id !== e.id); dirty = true">移除</el-button></li></ul><div class="s2-actions"><el-button :disabled="busy || !form.evidence" @click="execute('draft', { form })">保存核验草稿</el-button><el-button type="primary" :disabled="busy || !form.evidence" @click="execute('submit', { form })">提交核验</el-button></div></template>
      <template v-else-if="mode === 'transfer'"><label>转交处置人<select aria-label="转交处置人" v-model="target" :disabled="busy" @change="dirty = true"><option value="">请选择处置人</option><option v-for="a in options.filter(a => a.id !== user.user?.userId)" :key="a.id" :value="a.id">{{ a.name }}</option></select></label><el-button :disabled="busy || !target" @click="execute('transfer', { assigneeId: target })">确认转交</el-button></template>
      <template v-else><p>仅生成成功或失败的本地回执和时间线，未发送外部系统，也不改变原系统状态。</p><div v-for="channel in ['summary', 'verification']" :key="channel" class="s2-actions"><span>{{ channel === 'summary' ? '摘要回执' : '核验回执' }}</span><el-button :disabled="busy" @click="execute('receipt', { channel, result: 'SUCCESS' })">{{ channel === 'summary' ? '摘要' : '核验' }}本地成功</el-button><el-button :disabled="busy" @click="execute('receipt', { channel, result: 'FAILED' })">{{ channel === 'summary' ? '摘要' : '核验' }}本地失败</el-button></div></template>
      <p v-if="error" class="s2-error" role="alert">{{ error }}；版本冲突请关闭并重新打开，输入不会自动重试。</p><el-button :disabled="busy" @click="close">关闭编辑</el-button>
    </div>
  </el-dialog>
</template>
<style scoped>
.event-editor { max-height: 68vh; overflow-y: auto; padding: 4px 8px 8px 4px; }
.event-editor > label { display: grid; gap: 8px; }
.event-editor textarea { width: 100%; resize: vertical; min-height: 80px; padding: 10px; background: var(--input-bg); color: var(--text-primary); border: 1px solid var(--border); font: inherit; line-height: 1.6; }
.event-editor textarea:focus-visible { outline: 2px solid var(--cyan); outline-offset: 2px; }
.event-editor :deep(section[aria-label="资料证据选择器"]) { max-height: 240px; overflow-y: auto; padding: 8px; border: 1px solid var(--border); }
.event-editor li { overflow-wrap: anywhere; }
</style>
