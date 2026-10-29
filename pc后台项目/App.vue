<template><router-view /><ConfirmDialog /></template>
<script setup>
import { watchEffect, onBeforeUnmount } from 'vue'
import { useRoute } from 'vue-router'
const route = useRoute()
watchEffect(() => {
  const element = document.documentElement
  if (route.meta.adminTheme === 'business') {
    element.dataset.adminTheme = 'business'
    element.dataset.adminFamily = route.meta.adminFamily || 'list'
  } else { delete element.dataset.adminTheme; delete element.dataset.adminFamily }
})
onBeforeUnmount(() => { delete document.documentElement.dataset.adminTheme; delete document.documentElement.dataset.adminFamily })
import ConfirmDialog from './components/ConfirmDialog.vue'
</script>
