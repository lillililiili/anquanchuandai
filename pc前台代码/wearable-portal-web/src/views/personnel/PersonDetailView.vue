<script setup>
import ContactEntry from '@contact-entry'
import { computed, reactive, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { getPerson, getHistory } from '@/api/portal'
import { usePortalQuery } from '@/composables/usePortalQuery'
import { useContextStore } from '@/store/context'
import { useUserStore } from '@/store/user'
import { personIdPattern } from '@/utils/portal-route'
import { safeWorkspaceReturn } from '@/utils/spatial-contract'
import { formatTime, labels } from '@/utils/portal-contract'
import PortalPanel from '@/components/PortalPanel.vue'
import DataState from '@/components/personnel/DataState.vue'
import PersonIdentity from '@/components/personnel/PersonIdentity.vue'
import EquipmentTriplet from '@/components/personnel/EquipmentTriplet.vue'
import VitalSignsPanel from '@/components/personnel/VitalSignsPanel.vue'
import RelatedSection from '@/components/personnel/RelatedSection.vue'
import AssignmentActions from '@demo-assignment'
import { useBusinessRevision } from '@/composables/useBusinessRevision'
const route = useRoute(), context = useContextStore(), user = useUserStore()
const detail = reactive(usePortalQuery()), history = reactive(usePortalQuery())
const historyPage = ref(1)
const personId = computed(() => String(route.params.personId))
const siteId = computed(() => typeof route.query.siteId === 'string' ? route.query.siteId : context.selectedSiteId)
const returnTo = computed(() => safeWorkspaceReturn(route.query.returnTo))
async function reload() {
  history.clear()
  if (!user.token || context.state !== 'READY' || !context.data?.sites.some(s => s.siteId === siteId.value) || !personIdPattern.test(personId.value)) { detail.clear(); return }
  context.select(siteId.value)
  await detail.run(signal => getPerson(personId.value, siteId.value, signal))
}
async function loadHistory(page = 1) {
  historyPage.value = page
  if (!detail.data?.actions.viewHistory.allowed) { history.clear(); return }
  await history.run(signal => getHistory(personId.value, { siteId: siteId.value, pageNum: page, pageSize: 10 }, signal))
}
watch([personId, siteId, () => context.state, () => user.token], () => { historyPage.value = 1; reload() }, { immediate: true })
watch(() => detail.data, () => loadHistory(historyPage.value))
useBusinessRevision(['people', 'history'], reload)
</script>
<template>
  <div class="person-detail-page">
    <header class="personnel-page-heading"><router-link class="back-personnel" :to="returnTo">{{ returnTo.startsWith('/personnel') ? '← 返回人员列表' : '← 返回来源页面' }}</router-link><el-button :disabled="detail.state === 'LOADING'" @click="reload">刷新详情</el-button></header>
    <DataState v-if="!siteId || !personIdPattern.test(personId)" state="NOT_INTEGRATED" message="请选择有效厂站和人员后查看详情" />
    <DataState v-else-if="detail.state === 'LOADING'" state="LOADING" />
    <DataState v-else-if="detail.error" :state="detail.state" :message="detail.error.code === 404 ? '人员不存在或当前账号不可见' : detail.error.message" retry @retry="reload" />
    <div v-else-if="detail.data" class="person-detail-columns">
      <div class="person-detail-primary">
        <section class="person-summary-panel"><div><p class="v3-eyebrow">人员档案 / PERSONNEL</p><PersonIdentity :person="detail.data.person" large /></div><div class="person-summary-context"><span class="muted">{{ context.data?.sites.find(s => s.siteId === siteId)?.name || '厂站信息待接入' }}</span><ContactEntry :site-id="siteId" :person-id="personId" /></div></section>
        <VitalSignsPanel :site-id="siteId" :person-id="personId" showcase />
        <PortalPanel title="人员装备"><div class="equipment-concept"><img src="@/assets/images/v3-equipment.webp" alt="" loading="lazy" width="600" height="400" /><div><strong>三类装备 · 同一份守护</strong><p>概念装备示意，不代表厂家型号；以下领用关系与通信状态独立展示。</p></div></div><AssignmentActions :site-id="siteId" :person-id="personId" @changed="reload" /><EquipmentTriplet :section="detail.data.equipment" :site-id="siteId" :person-id="personId" /></PortalPanel>
        <PortalPanel title="当前位置"><div class="position-placeholder"><DataState :state="detail.data.location.state === 'AVAILABLE' ? 'NOT_INTEGRATED' : detail.data.location.state" :reason="detail.data.location.reasonCode" :message="detail.data.location.state === 'AVAILABLE' ? '地图展示暂未开放，不显示未经验证的位置' : ''" /></div></PortalPanel>
        <PortalPanel title="领用绑定历史">
          <DataState v-if="!detail.data.actions.viewHistory.allowed" :state="detail.data.historySummary.state === 'AVAILABLE' ? 'NOT_INTEGRATED' : detail.data.historySummary.state" :reason="detail.data.historySummary.reasonCode" />
          <DataState v-else-if="history.state === 'LOADING'" state="LOADING" />
          <DataState v-else-if="history.error" :state="history.state" :message="history.error.message" retry @retry="loadHistory(historyPage)" />
          <DataState v-else-if="history.data?.state !== 'AVAILABLE'" :state="history.data?.state" :reason="history.data?.reasonCode" />
          <template v-else><div class="table-scroll"><table class="people-table history-table"><thead><tr><th>操作 / 证据</th><th>装备编号</th><th>经办人</th><th>开始时间</th><th>结束时间</th><th>状态</th></tr></thead><tbody><tr v-for="item in history.data.items" :key="item.recordId"><td>{{ labels[item.action] || '未知' }}<small>{{ item.evidenceQuality === 'CONFIRMED' ? '证据已确认' : '历史证据不足' }}</small></td><td>{{ item.deviceCode }}</td><td>{{ item.operator?.displayName || '—' }}</td><td>{{ formatTime(item.startedAt) }}</td><td>{{ formatTime(item.endedAt) }}</td><td>{{ labels[item.state] }}</td></tr></tbody></table></div><DataState v-if="!history.data.items.length" state="EMPTY" compact /><AppPagination :current-page="historyPage" :page-size="10" :total="history.data.total" @current-change="loadHistory" /></template>
        </PortalPanel>
      </div>
      <div class="person-detail-secondary">
        <PortalPanel title="作业信息"><RelatedSection :section="detail.data.works" /></PortalPanel>
        <PortalPanel title="待现场核验事件"><RelatedSection :section="detail.data.events" kind="events" /></PortalPanel>
        <PortalPanel title="现场视频"><DataState :state="detail.data.media.state === 'AVAILABLE' ? 'NOT_INTEGRATED' : detail.data.media.state" :reason="detail.data.media.reasonCode" message="现场视频暂未开放" /><div class="person-actions"><el-button disabled title="本阶段暂未开放">查看视频</el-button><el-button disabled title="真实对讲未接入；本地协同使用上方联系协助入口">真实对讲未接入</el-button><el-button disabled title="本阶段暂未开放">查看事件</el-button></div></PortalPanel>
      </div>
    </div>
  </div>
</template>
