<template><span class="assignment-entry"><button class="button" :disabled="blocked" @click="store.assignmentIntent = { mode, personId, deviceId }">{{ label || (mode === 'issue' ? '办理领用' : '办理归还') }}</button><small v-if="blocked" class="disabled-reason">{{ reason || '需人员及设备范围内的资产办理权限' }}</small></span></template>
<script setup>
import { computed } from 'vue'
import { getAdminProvider } from '@admin-provider'
import { useAdminStore } from '../store'
const props = defineProps({ mode: { type: String, default: 'issue' }, personId: String, deviceId: String, label: String, disabled: Boolean, reason: String })
const store = useAdminStore(), provider = getAdminProvider()
const blocked = computed(() => { void store.revision; return props.disabled || !provider.canAny('assets:write', store.siteId) || !provider.canAny('people:read', store.siteId) })
</script>
