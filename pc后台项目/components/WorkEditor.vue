<script setup>
import { computed, ref, watch } from 'vue'
import { useFormFeedback } from '../formFeedback'
import { localTime, toUtc } from '../time'

const props = defineProps({ record: Object, options: Object, siteId: String, busy: Boolean, error: Object, disabled: Boolean })
const emit = defineEmits(['save', 'close', 'dirty'])
const row = props.record || {}
const form = ref({ siteId: row.siteId || props.siteId, name: row.name || '', area: row.area || '',
  plannedStartAt: localTime(row.plannedStartAt, 'Asia/Shanghai'), plannedEndAt: localTime(row.plannedEndAt, 'Asia/Shanghai'),
  leader: row.leader || '', supervisor: row.supervisor || '', members: [...(row.members || [])], remarks: row.remarks || '' })
const initial = JSON.stringify(form.value), memberKeyword = ref('')
const { formRef, localErrors, errors, formError, focusErrors } = useFormFeedback(form, () => props.error, 'work-')
const people = computed(() => (props.options?.people || []).filter(p => p.siteId === form.value.siteId))
const candidates = computed(() => people.value.filter(p => `${p.name} ${p.code || ''}`.includes(memberKeyword.value.trim())))
const participantIds = computed(() => [...new Set([...form.value.members, form.value.leader, form.value.supervisor].filter(Boolean))])
watch(form, () => emit('dirty', JSON.stringify(form.value) !== initial), { deep: true })
async function submit() {
  if (props.busy || props.disabled) return
  localErrors.value = {}
  for (const [key, label] of [['name','作业名称'], ['area','作业地点'], ['leader','负责人'], ['supervisor','监护人']]) {
    if (!form.value[key]?.trim()) localErrors.value[key] = `请${['leader','supervisor'].includes(key) ? '选择' : '填写'}${label}`
  }
  const body = { ...form.value, members: participantIds.value }
  for (const key of ['plannedStartAt', 'plannedEndAt']) {
    try { body[key] = toUtc(form.value[key], 'Asia/Shanghai') } catch (error) { localErrors.value[key] = error.message }
  }
  if (!localErrors.value.plannedStartAt && !localErrors.value.plannedEndAt && body.plannedEndAt <= body.plannedStartAt) localErrors.value.plannedEndAt = '结束时间必须晚于开始时间'
  if (!body.members.length) localErrors.value.members = '请选择参加人员'
  if (Object.keys(localErrors.value).length) { await focusErrors(); return }
  emit('save', { ...body, name: body.name.trim(), area: body.area.trim(), ...(props.record ? { expectedVersion: props.record.version } : {}) })
}
</script>

<template>
  <form ref="formRef" class="dialog-form master-form" novalidate @submit.prevent="submit">
    <div class="dialog-form-body">
      <p v-if="disabled" class="notice warning" role="alert">作业业务已关闭，当前填写已保留，重新开启后可继续保存。</p>
      <div class="work-editor-context"><span>{{ options?.sites?.find(s => s.id === form.siteId)?.name || form.siteId }}</span><span>本地登记{{ record ? ' · ' + record.id : ' · 编号由系统生成' }}</span></div>
      <div class="form-grid">
        <label><span class="field-label">作业名称<span class="required-mark">*</span></span><div class="field-control"><input id="work-name" v-model="form.name" maxlength="100" aria-required="true" :aria-invalid="!!errors.name" aria-describedby="error-work-name" /><small id="error-work-name" class="error">{{ errors.name }}</small></div></label>
        <label><span class="field-label">作业地点<span class="required-mark">*</span></span><div class="field-control"><input id="work-area" v-model="form.area" maxlength="200" aria-required="true" :aria-invalid="!!errors.area" aria-describedby="error-work-area" /><small id="error-work-area" class="error">{{ errors.area }}</small></div></label>
        <label><span class="field-label">计划开始时间<span class="required-mark">*</span></span><div class="field-control"><UiDatePicker id="work-plannedStartAt" v-model="form.plannedStartAt" type="datetime-local" aria-required="true" /><small class="error">{{ errors.plannedStartAt }}</small></div></label>
        <label><span class="field-label">计划结束时间<span class="required-mark">*</span></span><div class="field-control"><UiDatePicker id="work-plannedEndAt" v-model="form.plannedEndAt" type="datetime-local" aria-required="true" /><small class="error">{{ errors.plannedEndAt }}</small></div></label>
        <label><span class="field-label">负责人<span class="required-mark">*</span></span><div class="field-control"><UiSelect id="work-leader" v-model="form.leader" aria-required="true"><option value="">请选择负责人</option><option v-for="person in people" :key="person.id" :value="person.id">{{ person.name }}{{ person.code ? ' · ' + person.code : '' }}</option></UiSelect><small class="error">{{ errors.leader }}</small></div></label>
        <label><span class="field-label">监护人<span class="required-mark">*</span></span><div class="field-control"><UiSelect id="work-supervisor" v-model="form.supervisor" aria-required="true"><option value="">请选择监护人</option><option v-for="person in people" :key="person.id" :value="person.id">{{ person.name }}{{ person.code ? ' · ' + person.code : '' }}</option></UiSelect><small class="error">{{ errors.supervisor }}</small></div></label>
      </div>
      <p class="muted">时间按北京时间登记，可跨日。到达计划时间不会自动开始或结束。</p>
      <fieldset id="work-members"><legend>参加人员 · 已选 {{ participantIds.length }} 人<span class="required-mark">*</span></legend>
        <input v-model="memberKeyword" aria-label="搜索参加人员" placeholder="搜索姓名或编号" />
        <div class="choice-grid work-member-choices"><label v-for="person in candidates" :key="person.id"><input type="checkbox" :value="person.id" :checked="participantIds.includes(person.id)" :disabled="person.id === form.leader || person.id === form.supervisor" @change="form.members = $event.target.checked ? [...new Set([...form.members, person.id])] : form.members.filter(id => id !== person.id)" />{{ person.name }} <small v-if="person.id === form.leader || person.id === form.supervisor">（{{ person.id === form.leader ? '负责人' : '监护人' }}）</small></label></div>
        <p v-if="!candidates.length" class="muted">没有符合条件的有效人员。</p><small class="muted">负责人、监护人自动计入参加人员。</small><small class="error">{{ errors.members }}</small>
      </fieldset>
      <label>备注<div class="field-control"><textarea id="work-remarks" v-model="form.remarks" rows="3" maxlength="1000" /><small class="error">{{ errors.remarks }}</small></div></label>
      <div v-if="formError" class="form-submit-error error" data-form-error role="alert" tabindex="-1">{{ formError }}</div>
    </div>
    <div class="dialog-form-footer"><span class="muted">{{ record ? '版本 ' + record.version : '新增本地作业' }}</span><button class="button" type="button" :disabled="busy" @click="emit('close')">取消</button><button class="button primary" type="submit" :disabled="busy || disabled">{{ busy ? '正在保存…' : '保存登记' }}</button></div>
  </form>
</template>

<style scoped>
.work-editor-context{display:flex;justify-content:space-between;gap:12px;color:var(--text-muted,#93adc1);margin-bottom:18px}.work-member-choices{max-height:210px;overflow:auto;margin:12px 0}.work-member-choices label{display:flex;align-items:center;gap:8px}.work-member-choices input{width:17px;height:17px;flex:none}.work-member-choices small{font-size:12px}fieldset>small{display:block}.dialog-form-body>label{display:block;margin-top:16px}
</style>
