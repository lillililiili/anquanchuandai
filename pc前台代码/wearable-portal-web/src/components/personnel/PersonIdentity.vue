<script setup>
import { labels } from '@/utils/portal-contract'
defineProps({ person: { type: Object, required: true }, large: Boolean })
</script>
<template><div class="person-identity" :class="{ large }"><span class="person-avatar" aria-hidden="true">{{ person.name.slice(0, 1) }}</span><div><component :is="large ? 'h1' : 'strong'">{{ person.name }}</component><p>{{ person.personCode || '编号待接入' }} <span> · {{ person.team?.name || '班组待接入' }}</span></p><p v-if="large">{{ person.duty.state === 'AVAILABLE' ? labels[person.duty.data.state] : '在岗情况未知' }} · 手机：{{ person.phoneMasked || '—' }}</p></div></div></template>
