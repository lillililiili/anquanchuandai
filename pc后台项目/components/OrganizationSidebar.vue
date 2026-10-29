<template>
  <aside class="panel organization-sidebar" aria-label="组织">
    <div class="section-heading organization-heading">
      <div><h2>组织</h2><small class="muted">共 {{ nodes.length }} 个组织</small></div>
      <button class="button primary" :disabled="!ready || !writable" @click="$emit('create', null)">新增</button>
    </div>
    <label class="organization-search"><span class="sr-only">搜索组织</span><input v-model="keyword" placeholder="搜索组织名称或编号" maxlength="100" /></label>
    <button class="organization-all" :class="{ selected: !selectedId }" :aria-pressed="!selectedId" @click="$emit('select', null)">全部组织</button>
    <div class="organization-tree-scroll">
      <QueryState :loading="loading" :error="error" :data="data" @retry="$emit('retry')">
        <ul v-if="rows.length" class="organization-tree" aria-label="组织列表">
          <li v-for="entry in rows" :key="entry.node.id" class="organization-row" :class="{ selected: selectedId === entry.node.id }" :style="{ '--organization-depth': Math.min(entry.depth, 6) }">
            <button v-if="entry.hasChildren" class="organization-toggle" :aria-label="(entry.expanded ? '收起' : '展开') + entry.node.name" :aria-expanded="entry.expanded" @click="toggle(entry.node.id)"><span aria-hidden="true">{{ entry.expanded ? '▾' : '▸' }}</span></button>
            <span v-else class="organization-toggle-space" aria-hidden="true"></span>
            <button class="organization-name" :title="entry.node.name" :aria-pressed="selectedId === entry.node.id" @click="$emit('select', entry.node)"><span>{{ entry.node.name }}</span></button>
            <div class="organization-actions" role="group" :aria-label="entry.node.name + '操作'">
              <UiPopover label="⋯"><div class="row-more-content">
                <button class="button" @click="$emit('inspect', entry.node)">查看组织</button>
                <template v-if="writable">
                <button class="button" @click="$emit('create', entry.node)">新增下级组织</button>
                <button class="button" :disabled="!!entry.node.builtin" @click="$emit('edit', entry.node)">编辑组织</button>
                <button class="button danger" :disabled="!!entry.node.builtin" @click="$emit('delete', entry.node)">删除组织</button>
              </template></div></UiPopover>
            </div>
          </li>
        </ul>
        <p v-else class="muted organization-empty">{{ keyword ? '没有匹配的组织' : '暂无组织' }}</p>
      </QueryState>
    </div>
  </aside>
</template>
<script setup>
import { computed, ref, watch } from 'vue'
import UiPopover from '@ui-spec/UiPopover.vue'
import QueryState from './QueryState.vue'
import { organizationTreeRows } from '../organizationTree'
const props = defineProps({ nodes: { type: Array, default: () => [] }, selectedId: String, loading: Boolean, error: Object, data: Object, writable: Boolean })
defineEmits(['select', 'retry', 'create', 'edit', 'delete', 'inspect'])
const keyword = ref(''), collapsed = ref(new Set())
const ready = computed(() => !props.loading && !props.error && props.data?.availability === 'AVAILABLE')
const rows = computed(() => organizationTreeRows(props.nodes, { keyword: keyword.value, collapsed: collapsed.value }))
function toggle(id) { const next = new Set(collapsed.value); if (next.has(id)) next.delete(id); else next.add(id); collapsed.value = next }
watch(() => [props.selectedId, props.nodes], () => {
  const next = new Set(collapsed.value), seen = new Set()
  let parent = props.nodes.find(node => node.id === props.selectedId)?.parentId
  while (parent && !seen.has(parent)) { seen.add(parent); next.delete(parent); parent = props.nodes.find(node => node.id === parent)?.parentId }
  collapsed.value = next
})
</script>
