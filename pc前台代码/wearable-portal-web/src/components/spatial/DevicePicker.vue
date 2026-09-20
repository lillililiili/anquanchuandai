<script setup>
import { reactive, watch } from 'vue'
import { usePortalQuery } from '@/composables/usePortalQuery'
import { getDevices } from '@/api/spatial'
import { spatialLabels } from '@/utils/spatial-contract'
const props = defineProps({ siteId: { type: String, default: '' }, enabled: Boolean, modelValue: { type: String, default: '' } })
const emit = defineEmits(['update:modelValue'])
const query = reactive(usePortalQuery())
function load() {
  if (!props.enabled) { query.clear(); return }
  const siteId = props.siteId
  query.run(async signal => {
    const first = await getDevices({ siteId, pageNum: 1, pageSize: 100 }, signal)
    if (first.data.state !== 'AVAILABLE') return first
    const items = [...first.data.items]
    for (let pageNum = 2; items.length < first.data.total; pageNum++) {
      const next = await getDevices({ siteId, pageNum, pageSize: 100 }, signal)
      if (next.data.state !== 'AVAILABLE' || !next.data.items.length) throw new Error('设备列表发生变化，请重试')
      items.push(...next.data.items)
    }
    return { ...first, data: { ...first.data, items: [...new Map(items.map(item => [item.id, item])).values()] } }
  })
}
watch(() => [props.siteId, props.enabled], load, { immediate: true })
</script>
<template><div class="s2-device-picker"><label>设备<select :value="modelValue" :disabled="!enabled || query.state === 'LOADING' || query.data?.state !== 'AVAILABLE'" @change="emit('update:modelValue', $event.target.value)"><option value="">{{ query.data?.state === 'AVAILABLE' ? '请选择授权设备' : '设备来源待接入' }}</option><option v-if="modelValue && !query.data?.items.some(d => d.id === modelValue)" :value="modelValue">已选设备：{{ modelValue }}（由接口校验权限）</option><option v-for="d in query.data?.items" :key="d.id" :value="d.id">{{ d.deviceCode || d.name }} · {{ spatialLabels[d.type] }}</option></select></label><span v-if="query.error" role="status">{{ query.error.message }} <button type="button" class="s2-link" @click="load">重试</button></span></div></template>
