<template><button class="button" :disabled="!deviceId" @click="store.maintenanceIntent = { deviceId, orderId, type }">{{ label }}</button></template>
<script setup>
import { useAdminStore } from '../store'
defineProps({ deviceId: String, orderId: String, type: String, label: { type: String, default: '运维办理' } })
const store = useAdminStore()
</script>
