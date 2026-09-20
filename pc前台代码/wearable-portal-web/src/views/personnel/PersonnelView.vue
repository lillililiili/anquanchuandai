<script setup>
import { computed, reactive, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useContextStore } from '@/store/context'
import { getPeople, getPerson } from '@/api/portal'
import { usePortalQuery } from '@/composables/usePortalQuery'
import { personnelQuery } from '@/utils/portal-route'
import { formatTime } from '@/utils/portal-contract'
import DataState from '@/components/personnel/DataState.vue'
import PersonIdentity from '@/components/personnel/PersonIdentity.vue'
import EquipmentTriplet from '@/components/personnel/EquipmentTriplet.vue'
import PersonSideDetail from '@/components/personnel/PersonSideDetail.vue'
import { useBusinessRevision } from '@/composables/useBusinessRevision'
const route = useRoute(), router = useRouter(), context = useContextStore()
const list = reactive(usePortalQuery()), detail = reactive(usePortalQuery())
const filters = reactive({ keyword: '', teamId: '', shiftId: '', workState: '' })
const query = computed(() => personnelQuery(route.query))
const selectedId = computed(() => query.value.selectedPersonId || '')
const siteId = computed(() => query.value.siteId || context.selectedSiteId)
const pageNum = computed(() => Number(query.value.pageNum) || 1)
const pageSize = computed(() => Number(query.value.pageSize) || 20)
const availableSite = computed(() => context.data?.sites.some(s => s.siteId === siteId.value))
const teams = computed(() => context.data?.teams.filter(t => t.siteId === siteId.value) || [])
const shifts = computed(() => context.data?.shifts.filter(t => t.siteId === siteId.value) || [])
watch([siteId, availableSite], () => { if (availableSite.value) context.select(siteId.value) }, { immediate: true })
const listKey = computed(() => JSON.stringify({ ...query.value, selectedPersonId: undefined, siteId: siteId.value }))
useBusinessRevision(['people'], reload)
async function reload() {
  detail.clear()
  if (!availableSite.value) { list.clear(); return }
  const params = { ...query.value, siteId: siteId.value }
  delete params.selectedPersonId
  await list.run(signal => getPeople(params, signal))
  if (list.error?.code === 409) await context.load(true)
}
watch(() => route.query, () => { for (const key of Object.keys(filters)) filters[key] = query.value[key] || '' }, { immediate: true })
watch([listKey, () => context.state], () => { if (context.state === 'READY') reload(); else { list.clear(); detail.clear() } }, { immediate: true })
watch([selectedId, () => list.data], () => {
  detail.clear()
  if (selectedId.value && list.data?.items.some(p => p.personId === selectedId.value)) detail.run(signal => getPerson(selectedId.value, siteId.value, signal))
})
function search(reset = false) { router.push({ path: '/personnel', query: personnelQuery({ siteId: siteId.value, ...(reset ? {} : filters), pageSize: pageSize.value }) }) }
function selectPerson(personId) { router.replace({ path: '/personnel', query: { ...query.value, siteId: siteId.value, selectedPersonId: personId || undefined } }) }
function turnPage(n) { router.push({ path: '/personnel', query: { ...query.value, siteId: siteId.value, pageNum: String(n), selectedPersonId: undefined } }) }
function openPerson(id) { router.push({ name: 'person-detail', params: { personId: id }, query: { siteId: siteId.value, returnTo: route.fullPath } }) }
</script>
<template>
  <div class="personnel-page">
    <header class="personnel-page-heading"><h1>当班人员与装备</h1><p>以人员查看三类装备与当前作业</p></header>
    <div class="personnel-list-layout" :class="{ 'has-selection': !!selectedId }">
      <section class="personnel-list-main" aria-label="当班人员列表">
        <form class="personnel-filters" @submit.prevent="search()">
          <label class="keyword-filter"><span>姓名或人员编号</span><input v-model="filters.keyword" maxlength="100" placeholder="搜索姓名或人员编号" :disabled="!availableSite" /></label>
          <label><span>班组</span><select v-model="filters.teamId" :disabled="!teams.length"><option value="">全部班组</option><option v-for="t in teams" :key="t.teamId" :value="t.teamId">{{ t.name }}</option></select></label>
          <label><span>班次</span><select v-model="filters.shiftId" :disabled="!shifts.length"><option value="">当前班次</option><option v-for="s in shifts" :key="s.shiftId" :value="s.shiftId">{{ s.name }}</option></select></label>
          <label title="作业来源尚未接入"><span>作业状态</span><select v-model="filters.workState" disabled><option value="">待接入</option><option value="UNKNOWN">未知</option></select></label>
          <el-button native-type="submit" type="primary" :disabled="!availableSite">查询</el-button><el-button @click="search(true)">重置</el-button>
        </form>
        <div class="personnel-table-panel">
          <DataState v-if="context.state === 'LOADING' || context.state === 'IDLE'" state="LOADING" />
          <DataState v-else-if="context.state === 'ERROR'" state="ERROR" :message="context.error?.message" retry @retry="context.load(true)" />
          <DataState v-else-if="!availableSite" :state="siteId ? 'FORBIDDEN' : 'NOT_INTEGRATED'" :reason="context.data?.capabilities.people.reasonCode" :message="context.data?.sites.length ? (siteId ? '当前厂站不可访问，请重新选择' : '请在顶栏选择厂站') : ''" />
          <DataState v-else-if="list.state === 'LOADING'" state="LOADING" />
          <DataState v-else-if="list.error" :state="list.state" :message="list.error.message" retry @retry="reload" />
          <DataState v-else-if="list.data?.state !== 'AVAILABLE'" :state="list.data?.state" :reason="list.data?.reasonCode" />
          <template v-else>
            <div class="table-scroll"><table class="people-table"><thead><tr><th>序号</th><th>人员信息</th><th>所属区域 / 当前作业</th><th>装备状态</th><th>最近更新时间</th><th>操作</th></tr></thead><tbody>
              <tr v-for="(person, index) in list.data.items" :key="person.personId" :class="{ selected: person.personId === selectedId }" @click="selectPerson(person.personId)">
                <td>{{ (pageNum - 1) * pageSize + index + 1 }}</td><td><button class="person-row-button" :aria-pressed="person.personId === selectedId" @click.stop="selectPerson(person.personId)"><PersonIdentity :person="person" /></button></td>
                <td>{{ person.area?.name || '区域待接入' }}<small>{{ person.works.state === 'AVAILABLE' ? person.works.data.map(w => w.name).join('、') || '暂无作业' : '作业待接入' }}</small></td>
                <td><EquipmentTriplet :section="person.equipment" compact /></td><td>{{ formatTime(person.dataUpdatedAt) }}</td><td><el-button size="small" @click.stop="openPerson(person.personId)">查看详情</el-button></td>
              </tr>
            </tbody></table></div>
            <DataState v-if="!list.data.items.length" state="EMPTY" message="暂无当班人员" />
            <footer class="personnel-pagination"><AppPagination :current-page="pageNum" :page-size="pageSize" :total="list.data.total" @current-change="turnPage" /></footer>
          </template>
        </div>
        <p v-if="list.asOf" class="query-time">本次查询：{{ formatTime(list.asOf) }}（非设备上报时间）</p>
      </section>
      <aside v-if="selectedId" class="personnel-side" aria-label="所选人员详情">
        <DataState v-if="detail.state === 'LOADING'" state="LOADING" />
        <DataState v-else-if="detail.error" :state="detail.state" :message="detail.error.message" retry @retry="detail.run(signal => getPerson(selectedId, siteId, signal))" />
        <PersonSideDetail v-else-if="detail.data" :detail="detail.data" @close="selectPerson('')" @open="openPerson(selectedId)" />
        <DataState v-else state="IDLE" />
      </aside>
    </div>
  </div>
</template>
