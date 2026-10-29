<template>
  <form ref="formRef" class="master-form dialog-form" novalidate @submit.prevent="submit" @input="emit('dirty')" @change="emit('dirty')">
    <div class="dialog-form-body">
    <p v-if="row?.source === 'PLATFORM'" class="notice">设备编号与SN来自厂家，不能修改；其他资产资料可以补充。</p>
    <p v-if="row?.source === 'DIRECT_HELMET'" class="notice">一体帽的登录ID、平台编号与SN创建后不可修改；设备在线及通信能力以实际接入结果为准。</p>
    <p v-if="row?.source === 'DIRECT_BELT'" class="notice">安全带的登录ID、平台编号与SN创建后不可修改；设备在线、佩戴及挂钩状态以实际接入结果为准。</p>
    <fieldset :disabled="busy"><div class="form-grid">
      <label v-for="f in fields" :key="f.key" :class="{ wide: f.key === 'remark' }">{{ f.label }}{{ f.required ? ' *' : '' }}
        <div class="field-control"><textarea v-if="f.key === 'remark'" :id="'device-' + f.key" v-model="form[f.key]" :aria-label="f.label" rows="3" maxlength="500" />
        <UiDatePicker v-else-if="f.key === 'purchasedOn'" :id="'device-' + f.key" v-model="form[f.key]" :aria-label="f.label" :aria-invalid="Boolean(errors[f.key])" :aria-describedby="errors[f.key] ? 'error-' + f.key : undefined" />
        <input v-else :id="'device-' + f.key" v-model="form[f.key]" type="text" :aria-label="f.label" :aria-invalid="Boolean(errors[f.key])" :aria-describedby="errors[f.key] ? 'error-' + f.key : undefined" :disabled="Boolean(row && ((f.critical && row.keyEditReason) || (['PLATFORM','DIRECT_HELMET','DIRECT_BELT'].includes(row.source) && ['code','sn'].includes(f.key))))" maxlength="100" />
        <small v-if="errors[f.key]" :id="'error-' + f.key" class="error" aria-live="polite">{{ errors[f.key] }}</small></div>
      </label>
      <label>设备类型 *<div class="field-control"><UiSelect id="device-type" v-model="form.type" aria-label="设备类型" :disabled="Boolean(row)" @change="changeType"><option v-for="(name, key) in DEVICE_TYPES" :key="key" :value="key">{{ name }}</option></UiSelect><small v-if="errors.type" class="error" aria-live="polite">{{ errors.type }}</small></div></label>
      <label v-if="isDirectDeviceForm(form)" class="wide">设备登录ID *<div class="field-control"><input id="device-deviceNumber" v-model="form.deviceNumber" type="text" aria-label="设备登录ID" :aria-invalid="Boolean(errors.deviceNumber)" :aria-describedby="errors.deviceNumber ? 'error-deviceNumber device-number-help' : 'device-number-help'" :disabled="Boolean(row)" maxlength="64" /><small id="device-number-help">对应设备实际登录上报的 device_id，请以设备配置或上报日志为准；与铭牌SN、平台编号分别填写。建档后为未接入、未验证，收到真实上报后更新。</small><small v-if="errors.deviceNumber" id="error-deviceNumber" class="error" aria-live="polite">{{ errors.deviceNumber }}</small></div></label>
      <label>型号<div class="field-control"><input id="device-modelName" v-model="form.modelName" type="text" aria-label="型号" :aria-invalid="Boolean(errors.modelName)" :aria-describedby="errors.modelName ? 'error-modelName' : undefined" :disabled="Boolean(row?.keyEditReason)" maxlength="100" /><small v-if="errors.modelName" id="error-modelName" class="error" aria-live="polite">{{ errors.modelName }}</small></div></label>
    </div>
    <p v-if="row?.keyEditReason" class="notice">{{ row.keyEditReason }}。厂站及类型创建后不可修改。</p>
    </fieldset><p v-if="formError" class="form-submit-error error" data-form-error role="alert" tabindex="-1">{{ formError }}</p></div><div class="dialog-form-footer"><span class="muted">{{ row ? `版本 ${row.version}` : '新建：库存 · 未领用 · 通信未接入' }}</span><div class="actions"><button type="button" class="button" :disabled="busy" @click="emit('close')">取消</button><button class="button primary" :disabled="busy">{{ busy ? '保存中…' : '保存' }}</button></div></div>
  </form>
</template>
<script setup>
import { ref } from 'vue'
import { useFormFeedback } from '../formFeedback'
import { validateNativeControls } from '@ui-spec/useFieldErrors'
import { DEVICE_TYPES } from '../deviceData'
import { isDirectDeviceForm, deviceConnectionErrors, deviceSubmission } from '../deviceForm'
const props = defineProps({ row: Object, options: Object, busy: Boolean, error: Object })
const emit = defineEmits(['save', 'dirty', 'close'])
const fields = [{ key: 'code', label: '平台编号', required: true, critical: true }, { key: 'name', label: '设备名称', required: true }, { key: 'manufacturer', label: '厂商', critical: true }, { key: 'sn', label: 'SN', critical: true }, { key: 'assetCode', label: '资产编号' }, { key: 'purchasedOn', label: '购置日期' }, { key: 'remark', label: '备注' }]
const form = ref({ ...Object.fromEntries(fields.map(f => [f.key, props.row?.[f.key] || ''])), type: props.row?.type || 'HELMET', source: ['DIRECT_HELMET','DIRECT_BELT','PLATFORM'].includes(props.row?.source) ? props.row.source : 'LOCAL', deviceNumber: props.row?.deviceNumber || '', modelName: props.row?.modelName || '' })
const { formRef, localErrors, errors, formError, focusErrors } = useFormFeedback(form, () => props.error, 'device-')
function changeType() { form.value.source = 'LOCAL'; form.value.deviceNumber = '' }
function submit() {
  localErrors.value = deviceConnectionErrors(form.value, Boolean(props.row))
  for (const f of fields.filter(f => f.required)) if (!form.value[f.key].trim()) localErrors.value[f.key] = `请填写${f.label}`
  const controlsValid = validateNativeControls(formRef.value)
  if (Object.keys(localErrors.value).length) { focusErrors(); return }
  if (!controlsValid) return
  const data = deviceSubmission(form.value, Boolean(props.row))
  if (props.row && data.modelName === (props.row.modelName || '')) delete data.modelName
  emit('save', data)
}
</script>
