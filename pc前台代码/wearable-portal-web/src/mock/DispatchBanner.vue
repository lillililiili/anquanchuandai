<script setup>
import { computed } from 'vue'
import { useContextStore } from '@/store/context'
import { useWorkspaceStore } from '@/store/workspace'
import { useDispatchStore } from './dispatch-runtime'
import { readDataset } from './storage'
const dispatch = useDispatchStore(), context = useContextStore(), workspace = useWorkspaceStore()
const sos = computed(() => { workspace.revision; const d = readDataset(); if (d.config.module === 'events' && d.config.mode !== 'normal') return []; return d.entities.events.filter(e => e.siteId === context.selectedSiteId && /SOS$/.test(e.deviceReport?.category || '') && e.handlingStatus === 'UNHANDLED') })
</script>
<template><aside v-if="dispatch.active || sos.length" class="dispatch-banner" aria-label="协同与SOS提示"><router-link v-if="dispatch.active" :to="{ path: '/dispatch', query: { siteId: dispatch.active.siteId } }">本地会话进行中 · {{ dispatch.active.participants.filter(p => p.state === 'CONNECTED').length }}/{{ dispatch.active.participants.length }} 个对象本地会话就绪 · 打开会话</router-link><router-link v-if="sos.length" :to="{ path: '/dispatch/sos/' + sos[0].eventId, query: { siteId: context.selectedSiteId } }">模拟SOS未处理 {{ sos.length }} 件 · 查看最新求助</router-link></aside></template>
<style scoped>.dispatch-banner { display:flex; flex-wrap:wrap; gap:16px; margin-bottom:16px; padding:12px 16px; background:var(--panel-bg); border:1px solid var(--cyan); }.dispatch-banner a { color:var(--text-primary); font-size:13px; }</style>
