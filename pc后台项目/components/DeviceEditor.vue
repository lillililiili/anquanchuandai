<template>
  <form class="master-form" novalidate @submit.prevent="submit" @input="emit('dirty')" @change="emit('dirty')">
    <p class="notice">仅保存到当前页面，刷新重置。厂商、SN和型号可以稍后补充，不代表设备已接入。</p>
    <div v-if="error || Object.keys(localErrors).length" ref="summary" class="notice error" role="alert" tabindex="-1"><strong>未能保存，请检查资料</strong><p v-if="error">{{ error.message }} · {{ error.errorCode }} · {{ error.requestId }}</p><ul><li v-for="(message, field) in errors" :key="field"><a :href="'#device-' + field" @click.prevent="focus(field)">{{ message }}</a></li></ul></div>
    <fieldset :disabled="busy"><div class="form-grid">
      <label v-for="f in fields" :key="f.key" :class="{ wide: f.key === 'remark' }">{{ f.label }}{{ f.required ? ' *' : '' }}
        <textarea v-if="f.key === 'remark'" :id="'device-' + f.key" v-model="form[f.key]" :aria-label="f.label" rows="3" maxlength="500" />
        <input v-else :id="'device-' + f.key" v-model="form[f.key]" :type="f.key === 'purchasedOn' ? 'date' : 'text'" :aria-label="f.label" :aria-invalid="Boolean(errors[f.key])" :aria-describedby="errors[f.key] ? 'error-' + f.key : undefined" :disabled="Boolean(row && f.critical && row.keyEditReason)" maxlength="100" />
        <small v-if="errors[f.key]" :id="'error-' + f.key" class="error">{{ errors[f.key] }}</small>
      </label>
      <label>设备类型 *<select id="device-type" v-model="form.type" aria-label="设备类型" :disabled="Boolean(row)" @change="changeType"><option v-for="(name, key) in DEVICE_TYPES" :key="key" :value="key">{{ name }}</option></select></label>
      <label>所属区域<select id="device-areaId" v-model="form.areaId" aria-label="所属区域" :disabled="Boolean(row?.keyEditReason)"><option value="">未分配区域</option><option v-if="form.areaId && !options.areas.some(a => a.id === form.areaId)" :value="form.areaId">原区域（已停用或无权维护）</option><option v-for="a in options.areas" :key="a.id" :value="a.id" :disabled="!options.writableAreas.some(w => w.id === a.id)">{{ a.name }}</option></select><small v-if="errors.areaId" class="error">{{ errors.areaId }}</small></label>
      <label class="wide">型号模板<select id="device-modelId" v-model="form.modelId" aria-label="型号模板" :disabled="Boolean(row?.keyEditReason)" @change="changeModel"><option v-for="m in options.models.filter(m => m.type === form.type)" :key="m.id" :value="m.id">{{ m.name }}</option></select><small>{{ model?.declaration }}</small><small v-if="errors.modelId" class="error">{{ errors.modelId }}</small></label>
    </div>
    <p v-if="row?.keyEditReason" class="notice">{{ row.keyEditReason }}。厂站及类型创建后不可修改。</p>
    <fieldset id="device-assemblies"><legend>实例选配（本地配置）</legend><p v-if="!model?.options.length" class="muted">此模板暂无可配置选配，厂家能力待确认。</p><div class="form-grid"><label v-for="o in model?.options || []" :key="o.id">{{ o.name }}<select v-model="form.assemblies[o.id]" :aria-label="o.name" :disabled="Boolean(row?.keyEditReason)"><option v-for="(name, key) in ASSEMBLY" :key="key" :value="key">{{ name }}</option></select></label></div><small v-if="errors.assemblies" class="error">{{ errors.assemblies }}</small></fieldset>
    <div v-if="modelChanged" class="notice"><p>型号将变更。原选配配置将重置，移除不兼容项：{{ removed.join('、') || '无；仍需重新确认装配状态' }}。接入和真实验证状态不会改变。</p><label class="inline-check"><input v-model="form.confirmModelChange" type="checkbox" />我已确认型号变更及选配清理</label></div>
    <p v-if="!form.manufacturer.trim() || !form.sn.trim()" class="muted">厂家身份未完整核验：缺少厂商或SN，允许保存并待补充。</p>
    </fieldset><div class="form-footer"><span class="muted">{{ row ? `版本 ${row.version}` : '新建：库存 · 未领用 · 通信未接入' }}</span><div class="actions"><button type="button" class="button" :disabled="busy" @click="emit('close')">取消</button><button class="button primary" :disabled="busy">{{ busy ? '保存中…' : '保存本地设备' }}</button></div></div>
  </form>
</template>
<script setup>
import { ref, computed, watch, nextTick } from 'vue'
import { DEVICE_TYPES, ASSEMBLY } from '../deviceData'
const props = defineProps({ row: Object, options: Object, busy: Boolean, error: Object })
const emit = defineEmits(['save', 'dirty', 'close'])
const fields = [{ key: 'code', label: '平台编号', required: true, critical: true }, { key: 'name', label: '设备名称', required: true }, { key: 'manufacturer', label: '厂商', critical: true }, { key: 'sn', label: 'SN', critical: true }, { key: 'assetCode', label: '资产编号' }, { key: 'purchasedOn', label: '购置日期' }, { key: 'remark', label: '备注' }]
const form = ref({ ...Object.fromEntries(fields.map(f => [f.key, props.row?.[f.key] || ''])), type: props.row?.type || 'HELMET', areaId: props.row?.areaId || '', modelId: props.row?.modelId || 'unknown-HELMET', assemblies: { ...props.row?.assemblies }, confirmModelChange: false })
const summary = ref(null), localErrors = ref({})
const errors = computed(() => ({ ...localErrors.value, ...props.error?.fields }))
const model = computed(() => props.options.models.find(m => m.id === form.value.modelId))
const modelChanged = computed(() => props.row && form.value.modelId !== props.row.modelId)
const removed = computed(() => Object.keys(props.row?.assemblies || {}).filter(k => !model.value?.options.some(o => o.id === k)))
function changeModel() { form.value.assemblies = Object.fromEntries((model.value?.options || []).map(o => [o.id, 'UNKNOWN'])); form.value.confirmModelChange = false }
function changeType() { form.value.modelId = `unknown-${form.value.type}`; changeModel() }
function focus(key) { document.getElementById('device-' + key)?.focus() }
async function showErrors() { await nextTick(); summary.value?.focus() }
watch(() => props.error, e => { if (e) showErrors() })
function submit() {
  localErrors.value = {}
  for (const f of fields.filter(f => f.required)) if (!form.value[f.key].trim()) localErrors.value[f.key] = `请填写${f.label}`
  if (modelChanged.value && !form.value.confirmModelChange) localErrors.value.modelId = '请确认型号变更及选配清理'
  if (Object.keys(localErrors.value).length) { showErrors(); return }
  const data = JSON.parse(JSON.stringify(form.value)); if (props.row) delete data.type
  emit('save', data)
}
</script>
