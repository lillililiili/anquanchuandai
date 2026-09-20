<script setup>
import { showcaseImage } from '@/utils/demo-scenes'
import { deviceTypes, labels, formatTime, missingSection } from '@/utils/portal-contract'
import DeviceGlyph from './DeviceGlyph.vue'
import DataState from './DataState.vue'
import EquipmentActions from '@/components/equipment/EquipmentActions.vue'
import DeviceProfile from '@/components/equipment/DeviceProfile.vue'
defineProps({ section: { type: Object, default: () => missingSection() }, compact: Boolean, summary: Boolean, personId: String, siteId: String })
function assignment(slot) { return slot.assignmentState === 'UNKNOWN' ? '领用情况未知' : labels[slot.assignmentState] }
</script>
<template>
  <DataState v-if="section.state !== 'AVAILABLE'" :state="section.state" :reason="section.reasonCode" :compact="compact" />
  <div v-else class="equipment-triplet" :class="{ compact, summary }">
    <article v-for="(label, key) in deviceTypes" :key="key" class="equipment-card" :data-equipment-type="key">
      <figure v-if="!compact" class="equipment-product-photo"><img :src="showcaseImage(key === 'belt' ? 'harness' : key)" :alt="label + '概念展示'" loading="lazy" width="400" height="400" /><figcaption>概念装备 · 非厂家实物</figcaption></figure>
      <div class="equipment-title"><DeviceGlyph :type="key" /><strong>{{ label }}</strong></div>
      <span class="status-label" :data-state="section.data[key].assignmentState">{{ compact && section.data[key].assignmentState === 'UNKNOWN' ? '领用未知' : assignment(section.data[key]) }}</span>
      <div v-for="device in section.data[key].devices" :key="device.deviceId" class="device-reading">
        <span class="device-code">{{ device.deviceCode }}</span>
        <span class="status-label" :data-state="device.communication.state">{{ labels[device.communication.state] }}</span>
        <small v-if="compact && device.communication.freshness === 'STALE'" data-state="STALE">数据已过期</small>
        <template v-if="!compact && !summary">
          <DeviceProfile :device="device" compact />
          <small>源时间：{{ formatTime(device.communication.sourceTime) }}</small>
          <small :data-state="device.communication.freshness">{{ device.communication.freshness === 'UNKNOWN' ? '数据时效未知' : labels[device.communication.freshness] }}</small>
          <small>电量：{{ device.battery.value === null ? '—' : device.battery.value + '%' }} · {{ device.battery.freshness === 'UNKNOWN' ? '时间未知' : labels[device.battery.freshness] }}</small>
          <small v-if="device.battery.sourceTime">电量时间：{{ formatTime(device.battery.sourceTime) }}</small>
        </template>
        <small v-if="summary">{{ device.model || '型号待确认' }} · {{ device.communication.freshness === 'STALE' ? '数据已过期' : '源时间：' + formatTime(device.communication.sourceTime) }}</small>
      </div>
      <small v-if="key !== 'helmet' && !compact">厂家能力待确认</small>
      <EquipmentActions v-if="personId && siteId" :person-id="personId" :site-id="siteId" :type="key.toUpperCase()" :state="section.data[key].assignmentState" />
    </article>
  </div>
</template>
