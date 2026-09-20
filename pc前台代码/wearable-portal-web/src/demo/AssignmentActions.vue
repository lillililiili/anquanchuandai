<script setup>
import { computed, ref, watch, onBeforeUnmount } from 'vue'
import { useUserStore } from '@/store/user'
import request from '@/utils/request'
const props = defineProps({ siteId: { type: String, required: true }, personId: { type: String, required: true } })
const emit = defineEmits(['changed'])
const user = useUserStore(), opened = ref(false), busy = ref(false), error = ref(''), choice = ref(''), data = ref(null)
const allowed = computed(() => user.permissions.includes('portal:equipment:assign'))
let abort, revision = 0
function clear() { revision++; abort?.abort(); opened.value = false; data.value = null; choice.value = ''; busy.value = false; error.value = '' }
watch(() => [props.siteId, props.personId, user.token], clear)
onBeforeUnmount(clear)
async function load() {
  const version = ++revision; abort?.abort(); abort = new AbortController(); busy.value = true; error.value = ''
  try { const r = await request.get('/api/portal/v1/equipment-assignments/options', { params: { siteId: props.siteId, personId: props.personId }, signal: abort.signal }); if (version === revision) data.value = r.data } catch (e) { if (version === revision && e.code !== 'ERR_CANCELED') error.value = e.message } finally { if (version === revision) busy.value = false }
}
async function open() { opened.value = true; await load() }
async function save(item) {
  if (busy.value || !item && !choice.value) return
  busy.value = true; error.value = ''; const version = revision
  try {
    await request.post(item ? `/api/portal/v1/equipment-assignments/${item.id}/return` : '/api/portal/v1/equipment-assignments', item ? { siteId: props.siteId, version: item.version } : { siteId: props.siteId, personId: props.personId, deviceId: choice.value }, { headers: { 'Idempotency-Key': crypto.randomUUID() }, signal: abort?.signal })
    if (version !== revision) return
    choice.value = ''; emit('changed'); await load()
  } catch (e) { if (version === revision && e.code !== 'ERR_CANCELED') error.value = e.message } finally { if (version === revision) busy.value = false }
}
</script>
<template>
  <div class="demo-assignment"><el-button :disabled="!allowed" @click="open">领用 / 归还</el-button><small>{{ allowed ? '操作将保存至独立数据库' : '当前账号只读，无装备领用权限' }}</small>
    <el-dialog v-model="opened" title="本地装备领用与归还" width="620px" :close-on-click-modal="false" @closed="clear">
      <p>不发送设备命令。领用、归还会生成数据库流水。</p><p v-if="error" role="alert">{{ error }}</p>
      <template v-if="data"><h3>当前领用</h3><p v-if="!data.current.length">暂无领用装备</p><div v-for="item in data.current" :key="item.id" class="assignment-row"><span>{{ item.code }}</span><el-button :disabled="busy" @click="save(item)">归还</el-button></div>
        <label for="demo-equipment">可领用装备</label><select id="demo-equipment" v-model="choice" :disabled="busy"><option value="">请选择装备</option><option v-for="item in data.available" :key="item.id" :value="item.id">{{ item.code }}</option></select>
      </template><p v-else>{{ busy ? '正在读取…' : '装备读取失败' }}</p>
      <template #footer><el-button :disabled="busy" @click="opened = false">关闭</el-button><el-button :disabled="busy || !choice" type="primary" @click="save(null)">{{ busy ? '处理中…' : '确认领用' }}</el-button></template>
    </el-dialog>
  </div>
</template>
<style scoped>
.demo-assignment { margin-bottom: 12px; }.demo-assignment small { margin-left: 12px; }.assignment-row { display: flex; justify-content: space-between; gap: 16px; margin: 12px 0; }label { display: block; margin: 20px 0 8px; }select { width: 100%; padding: 12px; background: var(--el-bg-color); color: var(--el-text-color-primary); }select:focus-visible { outline: 2px solid var(--el-color-primary); }[role=alert] { color: var(--el-color-danger); }
</style>
