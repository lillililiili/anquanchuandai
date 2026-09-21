<template>
  <section><div class="page-heading"><div><span class="eyebrow">人员组织 / 人员档案</span><h1>人员详情</h1></div><router-link class="button" :to="recordReturn(route.query.returnTo, '/admin/people')">返回人员列表</router-link></div>
    <div class="actions"><AssignmentEntry :person-id="String(route.params.personId)" :disabled="!query.data.value?.enabled" reason="人员停用或尚未完成查询" /><AssignmentEntry mode="return" :person-id="String(route.params.personId)" /></div>
    <QueryState :data="query.data.value" :loading="query.loading.value" :error="query.error.value" @retry="load">
      <template v-if="query.data.value?.id"><section class="panel person-header"><span class="person-monogram" aria-hidden="true">{{ query.data.value.name.slice(-1) }}</span><div><h2>{{ query.data.value.name }}</h2><p>{{ query.data.value.code }} · {{ query.data.value.enabled ? '启用' : '停用' }}</p><small>{{ query.data.value.id }}</small></div><span class="badge">{{ query.data.value.accountName ? '关联账号：' + query.data.value.accountName : '无关联账号 / 无权查看账号' }}</span></section>
        <div class="equipment-slots"><section v-for="(name, type) in TYPE_NAMES" :key="type" class="panel"><DeviceMark :type="type" /><h2>{{ name }}</h2><template v-if="query.data.value.equipment.some(d => d.type === type)"><div v-for="d in query.data.value.equipment.filter(d => d.type === type)" :key="d.id"><p>{{ d.code }}</p><span class="badge">{{ d.relation === 'ASSIGNED' ? '当前已领用' : '关系需要核实' }}</span><p class="muted">{{ d.startedAt || '领用开始时间未知' }} · {{ d.assignmentSource === 'MOCK_OPERATION' ? '本页本地办理' : '初始领用记录' }}</p></div></template><p v-else class="muted">{{ SLOT_NAMES[query.data.value.slots?.[type]] || '领用情况不明' }}</p><p v-if="type !== 'HELMET'" class="small muted">公共本地结构 · 厂家协议待确认</p></section></div>
        <section class="panel"><h2>人员资料</h2><dl class="record-fields"><dt>厂站</dt><dd>{{ store.sites.find(s => s.id === query.data.value.siteId)?.name }}</dd><dt>组织标识</dt><dd>{{ query.data.value.organizationId || '未关联' }}</dd><dt>区域标识</dt><dd>{{ query.data.value.areaId || '未关联' }}</dd><dt>备注</dt><dd>{{ query.data.value.remark || '暂无备注' }}</dd></dl></section>
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
import { SLOT_NAMES } from '../assignmentData'
const route = useRoute(), store = useAdminStore(), query = useQuery()
function load() { query.run('person', { entity: 'people', siteId: store.siteId, id: route.params.personId }) }
watch(() => [route.params.personId, store.siteId, store.revision], load, { immediate: true })
</script>
