<script setup>
import { computed } from 'vue'
import { useUserStore } from '@/store/user'
defineProps({ siteId: String, personId: String, workId: String, deviceId: String, eventId: String })
const user = useUserStore(), allowed = computed(() => user.roles.includes('owner'))
</script>
<template><router-link v-if="allowed" class="dispatch-entry" :to="{ path: '/dispatch', query: { siteId, personId, workId, deviceId, eventId } }">联系协助（本地）</router-link><span v-else class="dispatch-entry">协同操作仅负责人可用</span></template>
<style scoped>.dispatch-entry { display:inline-block; margin:8px 0; padding:8px 12px; border:1px solid var(--border); color:var(--cyan); font-size:13px; }</style>
