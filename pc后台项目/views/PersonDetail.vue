<template>
  <section><h1 class="sr-only">人员详情</h1><div class="section-heading"><router-link class="button" :to="recordReturn(route.query.returnTo, '/people')">返回人员列表</router-link></div>
    <div class="actions"><AssignmentEntry :person-id="String(route.params.personId)" :disabled="!query.data.value?.enabled" reason="人员停用或尚未完成查询" /><AssignmentEntry mode="return" :person-id="String(route.params.personId)" /></div>
    <QueryState :data="query.data.value" :loading="query.loading.value" :error="query.error.value" @retry="load">
      <template v-if="query.data.value?.id"><section class="panel person-header"><span class="person-monogram" aria-hidden="true">{{ query.data.value.name.slice(-1) }}</span><div><h2>{{ query.data.value.name }}</h2><p>{{ query.data.value.code }} · {{ personDutyStatusLabel(query.data.value.dutyStatus) }}</p><small>{{ query.data.value.id }}</small></div><span v-if="query.data.value.accountName" class="badge">关联账号：{{ query.data.value.accountName }}</span></section>
        <div class="equipment-slots"><section v-for="(name, type) in TYPE_NAMES" :key="type" class="panel"><DeviceMark :type="type" /><h2>{{ name }}</h2><template v-if="query.data.value.equipment.some(d => d.type === type)"><div v-for="d in query.data.value.equipment.filter(d => d.type === type)" :key="d.id"><p>{{ d.code }}</p><span class="badge">{{ d.relation === 'ASSIGNED' ? '当前已领用' : '关系需要核实' }}</span><p class="muted">领用时间：{{ beijingTime(d.startedAt) }}</p></div></template><p v-else class="muted">{{ SLOT_NAMES[query.data.value.slots?.[type]] || '领用情况不明' }}</p></section></div>
        <section class="panel"><h2>人员资料</h2><dl class="record-fields"><dt>厂站</dt><dd>{{ store.sites.find(s => s.id === query.data.value.siteId)?.name }}</dd><dt>组织</dt><dd>{{ query.data.value.organizationName || '未关联' }}</dd><template v-if="query.data.value.dutyStatusSource === 'MANUAL'"><dt>状态维护人</dt><dd>{{ query.data.value.dutyStatusUpdatedBy || '管理员' }}</dd><dt>状态维护时间</dt><dd>{{ beijingTime(query.data.value.dutyStatusUpdatedAt) }}</dd></template></dl></section>
        <AssignmentHistory :person-id="String(route.params.personId)" />
      </template>
    </QueryState>
  </section>
</template>
<script setup>
import { watch } from 'vue'
import { useRoute } from 'vue-router'
import { useAdminStore } from '../store'
import { useQuery } from '../useQuery'
import { TYPE_NAMES } from '../seed'
import { recordReturn } from '../navigation'
import QueryState from '../components/QueryState.vue'
import DeviceMark from '../components/DeviceMark.vue'
import AssignmentEntry from '../components/AssignmentEntry.vue'
import AssignmentHistory from '../components/AssignmentHistory.vue'
import { beijingTime } from '../tablePresentation'
import { SLOT_NAMES } from '../assignmentData'
import { personDutyStatusLabel } from '../../shared/person-duty.mjs'
const route = useRoute(), store = useAdminStore(), query = useQuery()
function load() { query.run('person', { entity: 'people', siteId: store.siteId, id: route.params.personId }) }
watch(() => [route.params.personId, store.siteId, store.revision], load, { immediate: true })
</script>
