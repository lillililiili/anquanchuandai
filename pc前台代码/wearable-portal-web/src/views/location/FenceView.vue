<script setup>
import { ref, watch, computed } from 'vue'
import { useS2Workspace } from '@/composables/useS2Workspace'
import { getFences, getFence } from '@/api/spatial'
import { spatialLabels, validRing } from '@/utils/spatial-contract'
import { formatTime } from '@/utils/portal-contract'
import WorkspaceState from '@/components/spatial/WorkspaceState.vue'
import VectorMap from '@/components/spatial/VectorMap.vue'
import FenceEditor from '@fence-editor'
import { enabled } from '@spatial-actions'
const { context, list, detail, query, selectedId, siteId, availableSite, reload, search, select, page } = useS2Workspace('fences', getFences, getFence)
const status = ref('')
watch(query, q => { status.value = q.status || '' }, { immediate: true })
const fences = computed(() => {
  if (!selectedId.value) return list.data?.items || []
  return detail.state === 'READY' && detail.data?.id === selectedId.value ? [detail.data] : []
})
watch(() => list.data, data => {
  if (data?.state === 'AVAILABLE' && !selectedId.value && data.items?.length) select(data.items[0].id)
})
</script>
<template>
  <FenceEditor :site-id="siteId" :item="detail.data" :available="availableSite" />
  <div v-if="!enabled" class="s2-readonly-bar"><span>本阶段仅支持查看，围栏写入未开放</span><el-button disabled>新建围栏</el-button></div>
  <div class="s2-fence-grid" :class="{ 'has-selection': !!selectedId }">
    <section class="s2-panel s2-list"><h2>围栏列表</h2><label class="s2-stacked-form">状态<select v-model="status" :disabled="!availableSite" @change="search({ status })"><option value="">全部状态</option><option value="ENABLED">启用</option><option value="DISABLED">停用</option><option value="UNKNOWN">未知</option></select></label>
      <WorkspaceState :context="context" :available-site="availableSite" :site-id="siteId" :query="list" @retry="reload"><div class="workspace-list-scroll" tabindex="0" aria-label="列表内容"><button v-for="f in list.data?.items" :key="f.id" class="s2-list-row" :class="{ selected: selectedId === f.id }" :aria-pressed="selectedId === f.id" @click="select(f.id)"><strong>{{ f.name }}</strong><span>{{ spatialLabels[f.status] }}</span><small>版本 {{ f.version || '未知' }}</small></button><p v-if="!list.data?.items.length" class="s2-note">暂无围栏记录</p></div><AppPagination v-if="list.data?.total" :current-page="Number(query.pageNum || 1)" :page-size="Number(query.pageSize || 20)" :total="list.data.total" @current-change="page" /></WorkspaceState>
    </section>
    <div class="s2-map-column"><VectorMap :fences="fences" :selected-fence-id="selectedId" message="暂无可展示的可靠围栏范围" @select-fence="select" /></div>
    <aside v-if="selectedId" class="s2-panel s2-detail"><h2>围栏详情</h2><WorkspaceState :context="context" :available-site="availableSite" :site-id="siteId" :query="detail" idle="请选择左侧围栏" @retry="detail.run(s => getFence(selectedId, siteId, s))"><template v-if="detail.data"><dl class="s2-details"><dt>围栏名称</dt><dd>{{ detail.data.name }}</dd><dt>关联厂站</dt><dd>{{ context.data?.sites.find(s => s.siteId === siteId)?.name || '未知' }}</dd><dt>范围</dt><dd>{{ validRing(detail.data) ? '来源已提供 WGS84 闭合范围' : '范围未知或坐标系暂不支持' }}</dd><dt>规则说明</dt><dd>{{ detail.data.rule || '规则待确认' }}</dd><dt>适用对象</dt><dd>{{ detail.data.appliesTo || '来源未确认' }}</dd><dt>状态</dt><dd>{{ spatialLabels[detail.data.status] }}</dd><dt>版本</dt><dd>{{ detail.data.version || '未知' }}</dd><dt>源时间</dt><dd>{{ formatTime(detail.data.sourceTime) }}</dd><dt>生效时间</dt><dd>{{ formatTime(detail.data.effectiveAt) }}</dd></dl></template></WorkspaceState><el-button disabled title="未接入进出记录，不从位置推算违规">查看进出记录</el-button></aside>
  </div><p class="s2-note">启停仅修改本地台账，不发送设备命令；历史版本只读。</p>
</template>
