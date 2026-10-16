<template>
  <form ref="formRef" class="master-form" novalidate @submit.prevent="submit">
    <p class="notice">常设协助组按人员维护；不等同于前台临时设备调度组。仅保存本地策略，未发送 SOS 或其他通知。</p>
    <div class="form-grid">
      <label>组编号<div class="field-control"><input id="group-code" v-model="form.code" maxlength="50" required :aria-invalid="!!errors.code" aria-describedby="group-code-error" /><small id="group-code-error" class="error" aria-live="polite">{{ errors.code }}</small></div></label>
      <label>组名称<div class="field-control"><input id="group-name" v-model="form.name" maxlength="100" required /><small class="error" aria-live="polite">{{ errors.name }}</small></div></label>
      <label>管理区域<div class="field-control"><UiSelect aria-label="管理区域" id="group-areaId" v-model="form.areaId" required><option value="">请选择</option><option v-for="area in candidates.areas" :key="area.id" :value="area.id">{{ area.name }}</option></UiSelect><small class="error" aria-live="polite">{{ errors.areaId }}</small></div></label>
      <label>负责人<div class="field-control"><UiSelect aria-label="负责人" id="group-leaderId" v-model="form.leaderId" required><option value="">请选择本组成员</option><option v-for="p in candidates.people.filter(p => form.personIds.includes(p.id))" :key="p.id" :value="p.id">{{ p.name }}</option></UiSelect><small class="error" aria-live="polite">{{ errors.leaderId }}</small></div></label>
    </div>
    <fieldset id="group-personIds" tabindex="-1"><legend>组内成员 · 已选 {{ form.personIds.length }} 人</legend><input v-model="keyword" aria-label="搜索协助组成员" placeholder="按姓名或编号搜索" /><div class="choice-grid"><label v-for="p in candidates.people.filter(p => (p.name + p.code).includes(keyword))" :key="p.id"><input v-model="form.personIds" type="checkbox" :value="p.id" />{{ p.name }} · {{ p.code }}</label></div><small class="error" aria-live="polite">{{ errors.personIds }}</small><p v-if="missing.length" class="notice warning">以下旧成员已停用或不可选，请明确移除：<button v-for="id in missing" :key="id" type="button" class="button" @click="form.personIds = form.personIds.filter(p => p !== id)">{{ record?.members?.find(p => p.id === id)?.name || id }} · 移除</button></p></fieldset>
    <fieldset id="group-sos" tabindex="-1"><legend>SOS 通知范围</legend><label class="inline-check"><input v-model="form.sos.enabled" type="checkbox" />启用组内本地通知策略</label><p class="muted">关闭时保留选择但不生效。负责人不会自动成为接收人；移除成员后需显式取消其接收资格。</p><div class="choice-grid"><label v-for="p in recipientOptions" :key="p.id"><input v-model="form.sos.recipientIds" type="checkbox" :value="p.id" />{{ p.name }}{{ form.personIds.includes(p.id) ? '' : '（已移出组，请取消接收）' }}</label></div><small class="error" aria-live="polite">{{ errors.sos }}</small></fieldset>
    <label>备注<div class="field-control"><textarea id="group-remark" v-model="form.remark" maxlength="500" /><small class="error" aria-live="polite">{{ errors.remark }}</small></div></label>
    <p v-if="formError" class="form-submit-error error" data-form-error role="alert" tabindex="-1">{{ formError }}</p>
    <div class="form-footer"><span class="muted">{{ record ? '版本 ' + record.version : '新建' }} · 刷新重置</span><button class="button" type="button" :disabled="busy" @click="$emit('close')">取消</button><button class="button primary" :disabled="busy">{{ busy ? '保存中…' : '保存协助组与策略' }}</button></div>
  </form>
</template>
<script setup>
import { computed, ref, watch } from 'vue'
import { useFormFeedback } from '../formFeedback'
const props = defineProps({ record: Object, candidates: Object, error: Object, busy: Boolean })
const emit = defineEmits(['save', 'dirty', 'close']), r = props.record
const form = ref({ code: r?.code || '', name: r?.name || '', areaId: r?.areaId || '', leaderId: r?.leaderId || '', personIds: [...(r?.personIds || [])], sos: r?.sos ? JSON.parse(JSON.stringify(r.sos)) : { enabled: false, recipientIds: [] }, remark: r?.remark || '' }), keyword = ref('')
const { formRef, localErrors, errors, formError, focusErrors } = useFormFeedback(form, () => props.error, 'group-')
const initial = JSON.stringify(form.value)
const missing = computed(() => form.value.personIds.filter(id => !props.candidates.people.some(p => p.id === id)))
const recipientOptions = computed(() => [...new Set([...form.value.personIds, ...form.value.sos.recipientIds])].map(id => props.candidates.people.find(p => p.id === id) || r?.members?.find(p => p.id === id) || { id, name: id }))
watch(form, () => emit('dirty', JSON.stringify(form.value) !== initial), { deep: true })
function submit() {
  localErrors.value = {}
  for (const [key, label] of [['code', '组编号'], ['name', '组名称'], ['areaId', '管理区域'], ['leaderId', '负责人']]) {
    if (!String(form.value[key]).trim()) localErrors.value[key] = `请${['areaId', 'leaderId'].includes(key) ? '选择' : '填写'}${label}`
  }
  if (Object.keys(localErrors.value).length) { focusErrors(); return }
  emit('save', JSON.parse(JSON.stringify(form.value)))
}
</script>
