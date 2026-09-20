<template>
  <ul class="data-tree"><li v-for="node in nodes.filter(n => (n.parentId || null) === parentId)" :key="node.id">
    <button class="tree-node" :class="{ selected: selectedId === node.id }" @click="$emit('select', node)"><span>{{ node.name }}</span><small>{{ node.enabled ? '启用' : '停用' }}</small></button>
    <TreeBranch v-if="nodes.some(n => n.parentId === node.id)" :nodes="nodes" :parent-id="node.id" :selected-id="selectedId" @select="$emit('select', $event)" />
  </li></ul>
</template>
<script setup>
defineProps({ nodes: { type: Array, default: () => [] }, parentId: { type: String, default: null }, selectedId: String })
defineEmits(['select'])
</script>
