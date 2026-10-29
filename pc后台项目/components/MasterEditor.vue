<template>
  <form ref="formRef" class="master-form dialog-form" novalidate @submit.prevent="submit">
    <div class="dialog-form-body">
    <div class="form-grid">
      <label v-if="!['accounts', 'roles', 'dutyShifts'].includes(entity)"><span class="field-label">编号<span class="required-mark" aria-hidden="true">*</span></span><div class="field-control"><input id="field-code" aria-required="true" v-model="form.code" maxlength="50" :aria-invalid="!!errors.code" aria-describedby="error-code" /><small id="error-code" class="error" aria-live="polite">{{ errors.code }}</small></div></label>
      <label v-if="entity === 'accounts'"><span class="field-label">登录名<span class="required-mark" aria-hidden="true">*</span></span><div class="field-control"><input id="field-loginName" aria-required="true" v-model="form.loginName" maxlength="50" :disabled="!!record" :aria-invalid="!!errors.loginName" aria-describedby="error-loginName" /><small id="error-loginName" class="error" aria-live="polite">{{ errors.loginName }}</small></div></label>
      <label v-if="entity === 'accounts' && !record"><span class="field-label">初始登录密码<span class="required-mark">*</span></span><div class="field-control"><input id="field-password" :aria-invalid="!!errors.password" aria-describedby="error-password" v-model="form.password" type="password" autocomplete="new-password" minlength="8" maxlength="72" /><small id="error-password" class="error" aria-live="polite">{{ errors.password }}</small><small>至少8个字符；三个终端使用同一账号凭据。</small></div></label>
      <label><span class="field-label">名称 / 姓名<span class="required-mark" aria-hidden="true">*</span></span><div class="field-control"><input id="field-name" aria-required="true" v-model="form.name" aria-label="名称 / 姓名" maxlength="100" :aria-invalid="!!errors.name" aria-describedby="error-name" /><small id="error-name" class="error" aria-live="polite">{{ errors.name }}</small></div></label>
      <label v-if="entity === 'organizations'">上级节点<div class="field-control"><UiSelect id="field-parentId" v-model="form.parentId"><option value="">根节点</option><option v-for="o in options[entity]?.filter(x => x.id !== record?.id)" :key="o.id" :value="o.id">{{ o.name }}</option></UiSelect><small id="error-parentId" class="error" aria-live="polite">{{ errors.parentId }}</small></div></label>
      <label v-if="entity === 'people'">组织<div class="field-control"><UiSelect id="field-organizationId" v-model="form.organizationId"><option value="">尚未关联</option><option v-for="o in options.organizations" :key="o.id" :value="o.id">{{ o.name }}</option></UiSelect><small class="error" aria-live="polite">{{ errors.organizationId }}</small></div></label>
    </div>
    <template v-if="entity === 'dutyShifts'">
      <div class="form-grid"><label>开始时间<div class="field-control"><UiDatePicker id="field-startsAt" v-model="form.localStart" type="datetime-local" /><small class="error" aria-live="polite">{{ errors.startsAt }}</small></div></label><label>结束时间<div class="field-control"><UiDatePicker id="field-endsAt" v-model="form.localEnd" type="datetime-local" /><small class="error" aria-live="polite">{{ errors.endsAt }}</small></div></label></div>
      <fieldset id="field-personIds"><legend>班次成员 · 已选 {{ form.personIds.length }} 人</legend><input v-model="memberKeyword" aria-label="搜索班次成员" placeholder="搜索编号或姓名" /><div class="choice-grid"><label v-for="p in options.people?.filter(p => (p.name + p.code).includes(memberKeyword))" :key="p.id"><input v-model="form.personIds" type="checkbox" :value="p.id" />{{ p.name }} · {{ p.code }}</label></div><small class="error" aria-live="polite">{{ errors.personIds }}</small></fieldset>
    </template>
    <section v-if="entity === 'accounts'" class="binding-card">
      <p v-if="legacyMultipleRoles" class="notice warning">该用户原来绑定了多个角色，请重新选择唯一角色后保存。</p>
      <label><span class="field-label">角色</span><div class="field-control">
        <UiSelect id="field-bindings" v-model="form.roleBinding.roleId" aria-label="角色" :aria-invalid="!!errors.bindings" aria-describedby="error-bindings" @change="form.roleSelectionConfirmed = true">
          <option v-if="legacyMultipleRoles && !form.roleSelectionConfirmed" value="" disabled>请选择唯一角色</option>
          <option v-else value="">未分配角色</option>
          <option v-if="form.roleBinding.roleId && !selectedAccountRole" :value="form.roleBinding.roleId" disabled>原角色已停用或不可分配，请重新选择</option>
          <option v-for="role in assignableRoles" :key="role.id" :value="role.id">{{ role.name }}</option>
        </UiSelect>
        <small id="error-bindings" class="error" aria-live="polite">{{ errors.bindings }}</small>
      </div></label>
    </section>
    <template v-if="entity === 'roles'">
      <fieldset id="field-operations"><legend>允许操作</legend><div class="choice-grid"><label v-for="op in OPERATIONS.filter(item => !item.startsWith('integrations:') && item !== 'groups:write')" :key="op"><input v-model="form.operations" type="checkbox" :value="op" />{{ operationNames[op] || op }}</label></div><small class="error" aria-live="polite">{{ errors.operations }}</small></fieldset>
      <label id="field-siteIds">厂站范围<div class="field-control"><UiSelect v-model="form.siteIds" multiple><option v-for="s in options.sites" :key="s.id" :value="s.id">{{ s.name }}</option></UiSelect><small class="error" aria-live="polite">{{ errors.siteIds }}</small></div></label>
    </template>
    <p v-if="entity === 'accounts' && errors.personId" class="form-submit-error error" data-form-error role="alert" tabindex="-1">{{ errors.personId }}</p>
    <div v-if="formError" class="form-submit-error error" data-form-error role="alert" tabindex="-1"><p>{{ formError }}</p><ul v-if="error?.impacts"><li v-for="item in error.impacts" :key="item.label + item.id">{{ item.label }}：{{ item.name }}</li></ul></div>
    </div><div class="dialog-form-footer"><span v-if="entity !== 'sites'" class="muted">{{ record ? '版本 ' + record.version : '新记录' }}</span><button class="button" type="button" :disabled="busy" @click="$emit('close')">取消</button><button class="button primary" type="submit" :disabled="busy">{{ busy ? '正在保存…' : '保存' }}</button></div>
  </form>
</template>
<script setup>
import { computed, ref, watch } from 'vue'
import { useFormFeedback } from '../formFeedback'
import { validateNativeControls } from '@ui-spec/useFieldErrors'
import { OPERATIONS, DELEGATE_ROLES } from '../access'
import { OPERATION_NAMES as operationNames } from '../operationLabels'
import { localTime, toUtc } from '../time'
const props = defineProps({ entity: String, record: Object, defaults: Object, options: Object, siteId: String, timezone: String, busy: Boolean, error: Object, isSystem: Boolean })
const emit = defineEmits(['save', 'close', 'dirty'])
const r = props.record ? JSON.parse(JSON.stringify(props.record)) : { ...props.defaults }, grant = r.grants?.[0]
const legacyMultipleRoles = props.entity === 'accounts' && (r.roleIds || []).length > 1
const initialRoleId = (r.roleIds || []).length === 1 ? r.roleIds[0] : ''
const form = ref({ code: r.code || '', name: r.name || '', loginName: r.loginName || '', password: '', timezone: r.timezone || 'Asia/Shanghai', parentId: r.parentId || '', organizationId: r.organizationId || '', remark: r.remark || '', personId: r.personId || '', personIds: [...(r.personIds || [])], localStart: localTime(r.startsAt, props.timezone), localEnd: localTime(r.endsAt, props.timezone), operations: [...(grant?.operations || [])], siteIds: [...(grant?.siteIds || [props.siteId])], roleSelectionConfirmed: !legacyMultipleRoles, roleBinding: { roleId: initialRoleId } })
const initial = JSON.stringify(form.value), memberKeyword = ref('')
const { formRef, localErrors, errors, formError, focusErrors } = useFormFeedback(form, () => props.error, 'field-', { localStart: 'startsAt', localEnd: 'endsAt', roleBinding: 'bindings', roleSelectionConfirmed: 'bindings' })
const assignableRoles = computed(() => props.options.roles?.filter(r => r.id !== 'system' && (props.isSystem || DELEGATE_ROLES.includes(r.id))) || [])
const selectedAccountRole = computed(() => assignableRoles.value.find(role => role.id === form.value.roleBinding.roleId))

watch(form, () => emit('dirty', JSON.stringify(form.value) !== initial), { deep: true })
async function submit() {
  localErrors.value = {}
  const data = JSON.parse(JSON.stringify(form.value))
  if (!data.name.trim()) localErrors.value.name = '请填写名称 / 姓名'
  if (!['accounts', 'roles', 'dutyShifts'].includes(props.entity) && !data.code.trim()) localErrors.value.code = '请填写编号'
  if (props.entity === 'accounts' && !data.loginName.trim()) localErrors.value.loginName = '请填写登录名'
  if (props.entity === 'accounts' && !props.record && data.password.length < 8) localErrors.value.password = '初始密码至少8个字符'
  if (props.entity === 'accounts' && !data.roleSelectionConfirmed) localErrors.value.bindings = '请重新选择唯一角色后保存'
  if (props.record) delete data.password
  if (props.entity === 'dutyShifts') {
    for (const [field, key] of [['startsAt', 'localStart'], ['endsAt', 'localEnd']]) { try { data[field] = toUtc(data[key], props.timezone) } catch (e) { localErrors.value[field] = e.message } }
  }
  const controlsValid = validateNativeControls(formRef.value)
  if (Object.keys(localErrors.value).length) { await focusErrors(); return }
  if (!controlsValid) return
  if (props.entity === 'accounts') {
    const binding = data.roleBinding
    data.bindings = binding.roleId ? [{ roleId: binding.roleId }] : []
  }
  delete data.roleBinding
  delete data.roleSelectionConfirmed
  emit('save', data)
}
</script>
