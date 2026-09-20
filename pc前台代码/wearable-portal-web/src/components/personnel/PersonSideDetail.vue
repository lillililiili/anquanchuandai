<script setup>
import { ref, watch } from 'vue'
import PersonIdentity from './PersonIdentity.vue'
import EquipmentTriplet from './EquipmentTriplet.vue'
import RelatedSection from './RelatedSection.vue'
import DataState from './DataState.vue'
import VitalSignsPanel from './VitalSignsPanel.vue'
const props = defineProps({ detail: { type: Object, required: true } })
defineEmits(['close', 'open'])
const tab = ref('person')
watch(() => props.detail.person.personId, () => { tab.value = 'person' })
</script>
<template>
  <div class="person-side-detail">
    <header class="side-person-heading"><PersonIdentity :person="detail.person" /><button class="icon-button" aria-label="关闭人员详情" @click="$emit('close')">×</button></header>
    <el-tabs v-model="tab" class="person-tabs" stretch>
      <el-tab-pane label="人员信息" name="person"><dl class="person-facts"><dt>所属区域</dt><dd>{{ detail.person.area?.name || '待接入' }}</dd><dt>手机</dt><dd>{{ detail.person.phoneMasked || '—' }}</dd></dl><h3>装备状态</h3><EquipmentTriplet :section="detail.equipment" :site-id="detail.person.siteId" :person-id="detail.person.personId" summary /><h3>关联作业</h3><RelatedSection :section="detail.works" /><h3>待核验事件</h3><RelatedSection :section="detail.events" kind="events" /></el-tab-pane>
      <el-tab-pane label="装备信息" name="equipment"><EquipmentTriplet :section="detail.equipment" :site-id="detail.person.siteId" :person-id="detail.person.personId" /><el-button :disabled="!detail.actions.viewHistory.allowed" @click="$emit('open')">查看领用记录</el-button><DataState v-if="!detail.actions.viewHistory.allowed" :state="detail.historySummary.state" :reason="detail.historySummary.reasonCode" compact /></el-tab-pane>
      <el-tab-pane label="作业信息" name="works"><RelatedSection :section="detail.works" /></el-tab-pane>
      <el-tab-pane label="事件信息" name="events"><RelatedSection :section="detail.events" kind="events" /></el-tab-pane>
    </el-tabs>
    <VitalSignsPanel :site-id="detail.person.siteId" :person-id="detail.person.personId" compact />
    <footer class="person-actions"><el-button type="primary" @click="$emit('open')">查看完整详情</el-button><el-button disabled title="本阶段暂未开放">查看视频</el-button><el-button disabled title="本阶段暂未开放">发起对讲</el-button></footer>
  </div>
</template>
