<script setup>
import { computed, ref, watch } from 'vue'
import { useS2Workspace } from '@/composables/useS2Workspace'
import { getLocations } from '@/api/spatial'
import { getPeople } from '@/api/portal'
import { personLocation } from '@/utils/person-location'
import { useBusinessRevision } from '@/composables/useBusinessRevision'
import IssuedDeviceSummary from '@/components/personnel/IssuedDeviceSummary.vue'
import { positionReason } from '@/utils/spatial-contract'
import { formatTime, labels } from '@/utils/portal-contract'
import VectorMap from '@/components/spatial/VectorMap.vue'
import WorkspaceState from '@/components/spatial/WorkspaceState.vue'
import DataState from '@/components/personnel/DataState.vue'
import { useWorkspaceStore } from '@/store/workspace'
const workspace = useWorkspaceStore()
const { route, router, context, list, query, selected, selectedId, siteId, availableSite, reload, search, select, page } = useS2Workspace('live', getPersonLocations)
const keyword = ref('')
useBusinessRevision(['people', 'equipment'], reload)
async function getPersonLocations(params, signal) {
  const response = await getPeople(params, signal)
  const results = await Promise.allSettled(response.data.items.map(person => getLocations({ siteId: params.siteId, keyword: person.personId, pageNum: 1, pageSize: 100 }, signal)))
  return { ...response, data: { ...response.data, items: response.data.items.map((person, index) => {
    const result = results[index]
    return personLocation(person, result.status === 'fulfilled' ? result.value.data.items : [], result.status === 'fulfilled' ? result.value.data.state : 'UNAVAILABLE')
  }) } }
}
function locationMessage(item) {
  if (item.position) return positionReason(item.position)
  if (item.locationState !== 'AVAILABLE') return '位置数据' + (labels[item.locationState] || '暂时无法读取')
  return '暂无可确认位置'
}
watch(selected, item => { if (item?.deviceId) workspace.select(siteId.value, item.deviceId) })
const sharedDevice = computed(() => workspace.selection.siteId === siteId.value ? workspace.selection.deviceId : '')
const mapped = computed(() => list.data?.items?.find(i => i.deviceId === sharedDevice.value))
watch([mapped, () => list.state], () => { if (mapped.value && !selectedId.value && list.state === 'READY') select(mapped.value.id) })
watch(query, q => { keyword.value = q.keyword || '' }, { immediate: true })
const points = computed(() => {
  const items = selectedId.value ? (selected.value ? [selected.value] : []) : list.data?.items || []
  return items.filter(i => i.position).map(i => ({ ...i.position, recordId: i.id }))
})
function person() { router.push({ name: 'person-detail', params: { personId: selected.value.personId }, query: { siteId: siteId.value, returnTo: route.fullPath } }) }
function track() { router.push({ path: '/location', query: { tab: 'tracks', siteId: siteId.value, deviceId: selected.value.deviceId } }) }
</script>
<template>
  <p v-if="sharedDevice && list.state === 'READY' && !mapped" class="s2-note" role="status">当前页没有与共享设备对应的人员位置，可选择人员查看。</p>
  <div class="s2-stats"><span>当班人员 <strong>未接入</strong></span><span>人员位置可查看 <strong>统计待接入</strong></span><span>位置待核验 <strong>统计待接入</strong></span><el-button :disabled="!availableSite || list.state === 'LOADING'" @click="reload">刷新快照</el-button></div>
  <div class="s2-location-grid"><section class="s2-panel s2-list"><h2>人员位置</h2><form class="s2-stacked-form" @submit.prevent="search({ keyword })"><label>人员姓名或编号<input v-model="keyword" :disabled="!availableSite" maxlength="100" placeholder="搜索人员姓名 / 编号" /></label><label>作业分组<select disabled><option>分组来源待接入</option></select></label><el-button native-type="submit" type="primary" :disabled="!availableSite">查询</el-button></form>
    <WorkspaceState :context="context" :available-site="availableSite" :site-id="siteId" :query="list" @retry="reload"><div class="workspace-list-scroll" tabindex="0" aria-label="列表内容"><button v-for="i in list.data?.items" :key="i.id" class="s2-list-row" :class="{ selected: selectedId === i.id }" :aria-pressed="selectedId === i.id" @click="select(i.id)"><strong>{{ i.name }}</strong><span class="person-location-meta">{{ i.personCode }} · {{ i.team?.name || '班组待确认' }}</span><IssuedDeviceSummary :equipment="i.equipment" /><small>{{ locationMessage(i) }}</small></button><DataState v-if="!list.data?.items.length" state="EMPTY" message="暂无匹配人员" /></div><AppPagination v-if="list.data?.total" :current-page="Number(query.pageNum || 1)" :page-size="Number(query.pageSize || 20)" :total="list.data.total" @current-change="page" /></WorkspaceState>
  </section><div class="s2-map-column"><VectorMap :points="points" :message="selected ? locationMessage(selected) : '暂无可展示的可靠位置'" @select="select"><aside v-if="selected" class="s2-position-card"><div class="s2-card-title"><h2>{{ selected.name }}</h2><button class="icon-button" aria-label="关闭位置详情" @click="select('')">×</button></div><IssuedDeviceSummary :equipment="selected.equipment" /><p>{{ locationMessage(selected) }}</p><dl class="s2-details"><dt>人员编号</dt><dd>{{ selected.personCode }}</dd><dt>定位设备</dt><dd>{{ selected.deviceCode || '暂无可确认的定位设备' }}</dd><dt>设备通信</dt><dd>{{ labels[selected.communication] || '未知' }}</dd><dt>源时间</dt><dd>{{ formatTime(selected.position?.sourceTime) }}</dd><dt>接收时间</dt><dd>{{ formatTime(selected.position?.receivedAt) }}</dd><dt>定位来源</dt><dd>{{ selected.position?.source || '未知' }}</dd><dt>坐标系</dt><dd>{{ selected.position?.coordinateSystem || '未知' }}</dd><dt>精度</dt><dd>{{ Number.isFinite(selected.position?.accuracyMeters) ? selected.position.accuracyMeters + ' 米（来源报告）' : '未知，未补造精度' }}</dd></dl><div class="s2-actions"><el-button type="primary" :disabled="!selected.deviceId" @click="track">历史轨迹</el-button><el-button :disabled="!selected.personId" @click="person">查看人员</el-button></div></aside></VectorMap><p class="s2-note">位置来自设备最近快照；不表示室内精确位置。RTK/UWB仅为能力声明，缺少坐标转换或配准依据时不落点。未知坐标系及无可靠位置不落点。{{ list.asOf ? '本次查询：' + formatTime(list.asOf) + '（非设备上报时间）' : '' }}</p></div></div>
</template>
