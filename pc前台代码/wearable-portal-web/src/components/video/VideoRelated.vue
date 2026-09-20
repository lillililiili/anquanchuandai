<script setup>
import DataState from '@/components/personnel/DataState.vue'
import { formatTime } from '@/utils/portal-contract'
defineProps({ title: { type: String, required: true }, section: { type: Object, default: null }, personLinks: Boolean, siteId: { type: String, default: '' }, returnTo: { type: String, default: '/video' } })
</script>
<template>
  <section class="video-related"><h3>{{ title }}</h3>
    <DataState v-if="section?.state !== 'AVAILABLE'" :state="section?.state" :reason="section?.reasonCode" compact />
    <DataState v-else-if="!section.data.length" state="EMPTY" compact />
    <ul v-else><li v-for="item in section.data" :key="item.id"><router-link v-if="personLinks" :to="{ path: '/personnel/' + item.id, query: { siteId, returnTo } }">{{ item.name }}</router-link><router-link v-else-if="item.monitorState" :to="{ path: '/supervision/' + item.id, query: { siteId: item.siteId } }">{{ item.name }} → 作业监护</router-link><strong v-else>{{ item.name }}</strong><small>{{ item.type || '类型未知' }} · {{ item.id }}</small><small>源时间：{{ formatTime(item.sourceTime) === '—' ? '未知' : formatTime(item.sourceTime) }}<span v-if="item.freshness === 'STALE'"> · 数据已过期</span></small><small v-if="title === '最近资料'">接收时间：{{ formatTime(item.receivedAt) }} · 仅元数据，文件访问未开放</small></li></ul>
  </section>
</template>
