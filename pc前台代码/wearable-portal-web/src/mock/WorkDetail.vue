<script setup>
import { computed, ref, watch } from 'vue'
import DataState from '@/components/personnel/DataState.vue'
import EquipmentTriplet from '@/components/personnel/EquipmentTriplet.vue'
import DeviceProfile from '@/components/equipment/DeviceProfile.vue'
import VitalSignsPanel from '@/components/personnel/VitalSignsPanel.vue'
import { phaseLabels, eventTime } from '@/utils/event-contract'
import { positionReason } from '@/utils/spatial-contract'
const props = defineProps({ data: { type: Object, required: true }, siteId: String, returnTo: String })
const personPage = ref(1)
const vitalPerson = ref(null)
const people = computed(() => props.data.people.data || [])
const displayed = computed(() => people.value.slice((personPage.value - 1) * 5, personPage.value * 5))
watch(() => props.data.work.workId, () => { personPage.value = 1 })
watch([() => props.siteId, () => props.data.work.workId, personPage], () => { vitalPerson.value = null })
watch(() => people.value.length, n => { personPage.value = Math.min(personPage.value, Math.max(1, Math.ceil(n / 5))) })
</script>
<template>
  <section class="work-detail-section"><h3>参与人员与作业前装备检查</h3><p class="work-note">当前装备与设备报告，不是历史装备快照。未知、冲突、过期需核实；人工记录与设备报告独立，不自动判断允许作业。</p>
    <DataState v-if="data.people.state !== 'AVAILABLE'" :state="data.people.state" :message="data.people.message" compact /><DataState v-else-if="!people.length" state="EMPTY" message="尚未关联参与人员" compact />
    <article v-for="p in displayed" :key="p.personId" class="work-person"><header class="work-heading"><router-link :to="{ path: '/personnel/' + p.personId, query: { siteId, returnTo } }">{{ p.name }} → 人员详情</router-link><small>{{ p.personId }}</small></header><EquipmentTriplet :section="p.equipment" summary />
      <details><summary>查看设备专属报告与能力依据</summary><div class="work-devices"><template v-for="slot in Object.values(p.equipment.data || {})" :key="slot.type"><DeviceProfile v-for="d in slot.devices" :key="d.deviceId" :device="d" /></template></div></details>
      <button type="button" class="work-btn" :aria-expanded="vitalPerson === p.personId" @click="vitalPerson = vitalPerson === p.personId ? null : p.personId">{{ vitalPerson === p.personId ? '收起生命体征' : '查看人形生命体征（本地）' }}</button>
      <VitalSignsPanel v-if="vitalPerson === p.personId" :site-id="siteId" :person-id="p.personId" />
      <div class="work-manual"><strong>人工检查记录（非许可）</strong><p v-if="!data.monitoring.checks.some(c => c.personId === p.personId)">尚无人工检查；不以设备报告补全。</p><p v-for="(c, index) in data.monitoring.checks.filter(c => c.personId === p.personId)" :key="index">{{ c.result === 'ACKNOWLEDGED' ? '已人工查看（非许可）' : '待进一步核实' }} · {{ c.note }}<small>{{ eventTime(c.recordedAt) }} · {{ c.actorId }}</small></p></div>
    </article><AppPagination v-if="people.length" :current-page="personPage" :page-size="5" :total="people.length" @current-change="personPage = $event" />
  </section>
  <div class="work-related-grid">
    <section class="work-detail-section"><h3>关联事件 · 独立处置</h3><DataState v-if="data.events.state !== 'AVAILABLE'" :state="data.events.state" :message="data.events.message" compact /><p v-else-if="!data.events.data.length">暂无明确关联的事件。</p><router-link v-for="e in data.events.data || []" :key="e.eventId" class="work-related" :to="{ path: '/alarms/' + e.eventId + '/verification', query: { siteId, returnTo } }"><strong>{{ e.title }}</strong><small>{{ phaseLabels[e.phase] }} · {{ e.eventId }}</small></router-link><p class="work-note">结束监护不会关闭事件，也不解释为风险消除。</p></section>
    <section class="work-detail-section"><h3>关联视频 · 点击进入</h3><DataState v-if="data.videos.state !== 'AVAILABLE'" :state="data.videos.state" :message="data.videos.message" compact /><p v-else-if="!data.videos.data.length">没有明确关联的视频设备。</p><router-link v-for="v in data.videos.data || []" :key="v.deviceId" class="work-related" :to="{ path: '/video/' + v.deviceId, query: { siteId, returnTo } }">{{ v.name }}<small>进入后手动播放；本地媒体不是现场直播</small></router-link></section>
    <section class="work-detail-section"><h3>参与人员最近位置</h3><DataState v-if="data.locations.state !== 'AVAILABLE'" :state="data.locations.state" :message="data.locations.message" compact /><p v-else-if="!data.locations.data.length">无可靠人员关联的位置快照，不推定设备佩戴人。</p><router-link v-for="p in data.locations.data || []" :key="p.id" class="work-related" :to="{ path: '/location', query: { siteId, tab: 'live', selectedId: p.id } }">{{ p.name || p.deviceId }}<small>{{ positionReason(p.position) }} · {{ eventTime(p.position?.sourceTime) }}</small></router-link></section>
    <section class="work-detail-section"><h3>作业关联资料</h3><DataState v-if="data.materials.state !== 'AVAILABLE'" :state="data.materials.state" :message="data.materials.message" compact /><p v-else-if="!data.materials.data.length">暂无有证据关联的资料。</p><router-link v-for="m in data.materials.data || []" :key="m.id" class="work-related" :to="{ path: '/materials', query: { siteId, selectedId: m.id } }">{{ m.name }}<small>采集：{{ eventTime(m.capturedAt) }} · 接收：{{ eventTime(m.receivedAt) }}</small></router-link></section>
  </div>
</template>
