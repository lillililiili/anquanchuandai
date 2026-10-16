<template><router-view /><ConfirmDialog /></template>
<script setup>
import { watchEffect, onBeforeUnmount } from 'vue'
import { useRoute } from 'vue-router'
const route = useRoute()
watchEffect(() => {
  const element = document.documentElement
  if (route.matched.some(record => record.path === '/admin') && route.path !== '/admin/login') {
    element.dataset.adminTheme = 'business'
    element.dataset.adminFamily = route.path === '/admin/overview' ? 'monitor' : /^\/admin\/(people|assets\/devices)\/[^/]+$/.test(route.path) ? 'detail' : 'list'
  } else { delete element.dataset.adminTheme; delete element.dataset.adminFamily }
})
onBeforeUnmount(() => { delete document.documentElement.dataset.adminTheme; delete document.documentElement.dataset.adminFamily })
import ConfirmDialog from './components/ConfirmDialog.vue'
</script>
