<script setup>
import { ref, computed, watch } from 'vue'
import { ElMessageBox, ElMessage } from 'element-plus'
import { read, command } from '@spatial-actions'
import { useLocalEditor } from './useLocalEditor'
import EvidencePicker from './EvidencePicker.vue'
import './spatial-editor.scss'
const props = defineProps({ siteId: String, item: Object, available: Boolean })
const mode = ref('import'), file = ref(null), capturedAt = ref(''), links = ref({}), options = ref({}), evidence = ref(null), preview = ref(null), resource = ref(''), previewOpen = ref(false)
const editingItem = ref(null)
function release() { if (resource.value) URL.revokeObjectURL(resource.value); resource.value = ''; preview.value = null; previewOpen.value = false }
const { user, open, dirty, busy, error, clear, close, run } = useLocalEditor(() => { file.value = null; links.value = {}; options.value = {}; evidence.value = null; capturedAt.value = ''; release() })
const allowed = computed(() => props.available && user.roles.includes('owner'))
const hasFile = computed(() => props.item?.source === 'BROWSER_MEMORY')
watch(() => [props.item?.id, props.item?.version], release)
watch(previewOpen, value => { if (!value) release() })
async function start(next) {
  clear(); mode.value = next; open.value = true
  editingItem.value = props.item ? { id: props.item.id, version: props.item.version } : null
  links.value = { personId: props.item?.personId || '', workId: props.item?.workId || '', eventId: props.item?.eventId || '' }
  if (next !== 'import') await run(async signal => { const r = await read('options', { siteId: props.siteId }, signal); if (!signal.aborted) options.value = r.data })
}
async function submit() {
  await run(async signal => {
    const base = { siteId: props.siteId, operationId: crypto.randomUUID() }
    if (mode.value === 'import') {
      if (!file.value) throw new Error('请选择本地文件')
      await command('material-import', { ...base, file: file.value, name: file.value.name, capturedAt: capturedAt.value ? new Date(capturedAt.value + 'Z').toISOString() : null }, signal)
    } else if (mode.value === 'associate') await command('material-associate', { ...base, ...links.value, id: editingItem.value.id, expectedVersion: editingItem.value.version }, signal)
    else {
      if (!evidence.value || !links.value.eventId) throw new Error('请选择事件与资料')
      await command('material-reference', { ...base, id: evidence.value.id, expectedVersion: evidence.value.version, eventId: links.value.eventId }, signal)
    }
    if (!signal.aborted) { dirty.value = false; clear(); ElMessage.success('已保存到页面内存；刷新后恢复初始数据') }
  })
}
async function show(download = false) {
  release()
  const target = props.item && { siteId: props.siteId, id: props.item.id, version: props.item.version }, token = user.token
  if (!target) return
  await run(async signal => {
    const r = await read('blob', { siteId: target.siteId, id: target.id }, signal)
    if (signal.aborted || user.token !== token || props.siteId !== target.siteId || props.item?.id !== target.id || props.item?.version !== target.version) return
    resource.value = URL.createObjectURL(r.data.blob)
    if (download) { const a = document.createElement('a'); a.href = resource.value; a.download = r.data.name; a.click(); release() }
    else { preview.value = r.data; previewOpen.value = true }
  })
}
async function remove() {
  const target = props.item && { siteId: props.siteId, id: props.item.id, expectedVersion: props.item.version }, token = user.token
  try { await ElMessageBox.confirm('删除该本地资料及内存文件？已冻结引用的版本不可删除。', '删除资料', { confirmButtonText: '确认删除', cancelButtonText: '取消' }) } catch { return }
  if (!target || props.siteId !== target.siteId || user.token !== token) return
  await run(async signal => { await command('material-delete', { ...target, operationId: crypto.randomUUID() }, signal); if (!signal.aborted) { release(); ElMessage.success('已删除内存资料；刷新可恢复种子，不恢复用户导入文件') } })
}
</script>
<template>
  <section class="local-toolbar" aria-label="本地资料操作"><p>本地资料 · 内存文件可预览；设备本地录像、元数据存在不等于平台可播放</p><div class="s2-actions"><el-button :disabled="!allowed || busy" @click="start('import')">导入本地资料</el-button><el-button :disabled="!hasFile || busy" @click="show()">预览所选资料</el-button><el-button :disabled="!hasFile || busy" @click="show(true)">下载所选资料</el-button><el-button :disabled="!allowed || !item || item.frozen || busy" @click="start('associate')">人工关联</el-button><el-button :disabled="!allowed || busy" @click="start('reference')">选择事件证据</el-button><el-button :disabled="!allowed || !item || item.frozen || busy" @click="remove">删除资料</el-button></div><small>{{ !allowed ? '仅负责人可导入、关联或删除；其他身份只读。' : item?.frozen ? '所选资料版本已冻结，不允许覆盖或删除。' : '单文件50MB，总预算200MB；刷新清空文件。不上传网络。' }}</small><small v-if="item && !hasFile">所选资料仅有元数据，文件尚未接入，无法预览下载。</small><p v-if="item?.attribution === 'MANUAL_MOCK'">人工关联，非设备采集时人员归属证据。</p><p v-if="error && !open" role="alert">{{ error }}</p></section>
  <el-dialog :model-value="open" :title="mode === 'import' ? '导入本地资料（仅内存）' : mode === 'associate' ? '人工关联' : '冻结事件证据引用'" width="min(760px, 94vw)" append-to-body :close-on-click-modal="false" :before-close="close">
    <form class="local-editor" @submit.prevent="submit">
      <template v-if="mode === 'import'"><label>本地文件<input type="file" accept=".jpg,.jpeg,.png,.webp,.mp4,.webm,.mp3,.wav,.ogg" :disabled="busy" @change="file = $event.target.files[0] || null; dirty = !!file" /></label><p>支持JPEG/PNG/WebP、MP4/WebM、MP3/WAV/OGG，检查内容及浏览器解码。禁止SVG、HTML或任意URL。选择文件不会自动导入。</p><label>采集时间（UTC，可留空）<input v-model="capturedAt" type="datetime-local" :disabled="busy" @input="dirty = true" /></label><p>导入时间单独保存；不把导入时间或当前佩戴人作为拍摄时间、历史归属。</p></template>
      <template v-else><div class="local-fields"><label v-if="mode === 'associate'">关联人员<select aria-label="关联人员" v-model="links.personId" :disabled="busy" @change="dirty = true"><option value="">未知/无关联</option><option v-for="p in options.people" :key="p.id" :value="p.id">{{ p.name }}</option></select></label><label v-if="mode === 'associate'">关联作业<select aria-label="关联作业" v-model="links.workId" :disabled="busy" @change="dirty = true"><option value="">未知/无关联</option><option v-for="p in options.works" :key="p.id" :value="p.id">{{ p.name }}</option></select></label><label>关联事件<select aria-label="关联事件" v-model="links.eventId" :disabled="busy" @change="dirty = true"><option value="">请选择事件</option><option v-for="p in options.events" :key="p.id" :value="p.id">{{ p.name }}</option></select></label></div><p>所有选择均为人工关联，不能证明历史佩戴人，不改变过去事件或核验记录。</p><EvidencePicker v-if="mode === 'reference'" :site-id="siteId" @select="item => { evidence = item; dirty = !!item }" /><p v-if="mode === 'reference'">冻结后该版本不可覆盖、删除；不提交核验或完成事件。</p></template>
      <p v-if="error" role="alert" class="s2-error">{{ error }}</p><div class="s2-actions"><el-button :disabled="busy" @click="close">取消</el-button><el-button type="primary" native-type="submit" :loading="busy" :disabled="busy || !allowed">{{ mode === 'import' ? '确认导入' : mode === 'associate' ? '保存人工关联' : '冻结引用' }}</el-button></div>
    </form>
  </el-dialog>
  <el-dialog v-model="previewOpen" title="本地内存资料预览" width="min(900px, 94vw)" append-to-body destroy-on-close><template v-if="preview && resource"><p>{{ preview.name }} · 版本{{ preview.version }} · 非现场直播</p><img v-if="preview.type === 'PHOTO'" class="local-preview" :src="resource" :alt="preview.name" /><video v-else-if="preview.type === 'VIDEO'" class="local-preview" :src="resource" controls preload="metadata" /><audio v-else class="local-preview" :src="resource" controls preload="metadata" /><p>关闭预览会释放临时地址，未删除的内存文件仍可再次打开。</p></template></el-dialog>
</template>
