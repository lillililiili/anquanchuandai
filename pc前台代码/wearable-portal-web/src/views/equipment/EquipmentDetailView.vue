<script setup>
import { computed, reactive, watch } from 'vue'
import { useRoute } from 'vue-router'
import { useContextStore } from '@/store/context'
import { useUserStore } from '@/store/user'
import { usePortalQuery } from '@/composables/usePortalQuery'
import { useBusinessRevision } from '@/composables/useBusinessRevision'
import { getEquipmentDetail } from '@/api/equipment'
import { equipmentTypes, assignmentLabels, safeEquipmentReturn } from '@/utils/equipment-route'
import { formatTime, labels } from '@/utils/portal-contract'
import WorkspaceState from '@/components/spatial/WorkspaceState.vue'
import EquipmentActions from '@/components/equipment/EquipmentActions.vue'
import DeviceProfile from '@/components/equipment/DeviceProfile.vue'
import DeviceGlyph from '@/components/personnel/DeviceGlyph.vue'
import VitalSignsPanel from '@/components/personnel/VitalSignsPanel.vue'
import '@/styles/equipment.scss'
const route = useRoute(), context = useContextStore(), user = useUserStore(), detail = reactive(usePortalQuery())
const siteId = computed(() => route.query.siteId || context.selectedSiteId), deviceId = computed(() => String(route.params.deviceId))
const availableSite = computed(() => context.state === 'READY' && !!user.token && context.data?.sites.some(s => s.siteId === siteId.value))
const device = computed(() => detail.data?.device)
const returnTo = computed(() => safeEquipmentReturn(route.query.returnTo || '/equipment?siteId=' + siteId.value))
function reload() { if (!availableSite.value) return detail.clear(); context.select(siteId.value); detail.run(signal => getEquipmentDetail(deviceId.value, siteId.value, signal)) }
watch(() => [siteId.value, deviceId.value, availableSite.value, user.token], reload, { immediate: true })
useBusinessRevision(['equipment'], reload)
</script>
<template><section class="equipment-page">
  <header class="equipment-heading"><div><router-link :to="returnTo">← 返回装备列表</router-link><h1>装备详情</h1></div><el-button :disabled="!availableSite" @click="reload">刷新详情</el-button></header>
  <WorkspaceState :context="context" :site-id="siteId" :available-site="availableSite" :query="detail" @retry="reload">
    <div v-if="device" class="equipment-detail-grid">
      <section class="equipment-panel"><div class="equipment-identity"><DeviceGlyph :type="device.type.toLowerCase()" /><div><p>{{ equipmentTypes[device.type] }}</p><h2>{{ device.name }}</h2></div></div><strong class="equipment-code">{{ device.deviceCode }}</strong><dl><dt>设备标识</dt><dd>{{ device.deviceId }}</dd><dt>领用状态</dt><dd>{{ assignmentLabels[device.assignmentState] }}</dd><dt>通信状态</dt><dd>{{ labels[device.communication.state] }}</dd><dt>数据时效</dt><dd>{{ labels[device.communication.freshness] }}</dd><dt>设备源时间</dt><dd>{{ formatTime(device.communication.sourceTime) === '—' ? '未知' : formatTime(device.communication.sourceTime) }}</dd><dt>电量</dt><dd>{{ device.battery.value === null ? '未知' : device.battery.value + '%' }} · {{ labels[device.battery.freshness] }}</dd><dt>电量源时间</dt><dd>{{ formatTime(device.battery.sourceTime) }}</dd></dl><p class="equipment-note">领用操作不更新设备上报时间、通信或电量。</p></section>
      <section class="equipment-panel"><h2>当前领用关系</h2><template v-if="device.currentPerson"><h3>{{ device.currentPerson.name }}</h3><dl><dt>人员编号</dt><dd>{{ device.currentPerson.personCode }}</dd><dt>关系标识</dt><dd>{{ device.currentAssignment.assignmentId }}</dd><dt>领用时间</dt><dd>{{ device.currentAssignment.startedAt ? formatTime(device.currentAssignment.startedAt) : '未知：当前关系快照，不是领用流水' }}</dd></dl><router-link :to="{ path: '/personnel/' + device.currentPerson.personId, query: { siteId, returnTo: route.fullPath } }">查看人员及领用历史 →</router-link></template><p v-else>{{ device.assignmentState === 'UNASSIGNED' ? '已明确未领用，无当前领用人。' : '关系未知或冲突，不能推定当前领用人。' }}</p><EquipmentActions :site-id="siteId" :device-id="device.deviceId" :type="device.type" :state="device.assignmentState" /><p class="equipment-note">不支持强制解绑、异常关系修复或设备配置。</p></section>
      <section class="equipment-panel"><h2>能力说明</h2><DeviceProfile :device="device" /><p class="equipment-note">本页不会建立媒体连接或发送设备命令。</p></section>
      <VitalSignsPanel v-if="device.type === 'WATCH'" class="equipment-vitals" :site-id="siteId" :device-id="device.deviceId" />
    </div>
  </WorkspaceState>
</section></template>
<style scoped>.equipment-vitals { grid-column: 1 / -1; }</style>
