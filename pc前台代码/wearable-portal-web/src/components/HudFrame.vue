<script setup>
defineOptions({ inheritAttrs: false })
defineProps({ tag: { type: String, default: 'div' } })
</script>
<template>
  <component :is="tag" v-bind="$attrs" class="hud-frame"><slot /></component>
</template>
