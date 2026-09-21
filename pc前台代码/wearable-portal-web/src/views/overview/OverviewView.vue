<script setup>
import { alarmLabel } from '@/utils/alarm-contract'
import { computed, reactive, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { useContextStore } from '@/store/context'
import { useUserStore } from '@/store/user'
import { useWorkspaceStore } from '@/store/workspace'
import { usePortalQuery } from '@/composables/usePortalQuery'
import { getWorkbench } from '@workbench-provider'

import { workspaceTarget } from '@/utils/workspace-navigation'
import DataState from '@/components/personnel/DataState.vue'
import AppIcon from '@/components/AppIcon.vue'
import SceneGallery from '@/components/SceneGallery.vue'
import { showcaseImage } from '@/utils/demo-scenes'
const context = useContextStore(), user = useUserStore(), workspace = useWorkspaceStore(), route = useRoute()
const result = reactive(usePortalQuery()), drill = ref(''), page = ref(1)
const siteId = computed(() => route.query.siteId || context.selectedSiteId)
const authorized = computed(() => context.state === 'READY' && context.data?.sites.some(s => s.siteId === siteId.value))
const metrics = [{ key: 'duty', title: '当班人数', note: '名册人员去重，不代表在线人数' }, { key: 'equipment', title: '已领用装备数', note: '明确已领用设备；未知及冲突不计入' }, { key: 'open', title: '未处理告警数', note: '尚未填写处理记录的设备告警' }, { key: 'mine', title: '可处理告警数', note: '当前身份有权限直接处理的未处理告警' }]
const section = key => result.data?.[key]
const rows = computed(() => section(drill.value)?.data || [])
const visibleRows = computed(() => rows.value.slice((page.value - 1) * 20, page.value * 20))
const titles = { ...Object.fromEntries(metrics.map(m => [m.key, m.title])), unknown: '处理状态未知事件' }
function open(key) { drill.value = key; page.value = 1 }
function reload() { drill.value = ''; if (!authorized.value || !user.token) return result.clear(); context.select(siteId.value); result.run(signal => getWorkbench(siteId.value, signal)) }
watch(() => [siteId.value, authorized.value, user.token, workspace.revision], reload, { immediate: true })
const eventTarget = e => ({ path: '/alarms/' + e.eventId, query: { siteId: siteId.value, returnTo: '/overview?siteId=' + siteId.value } })
const count = key => section(key)?.state === 'AVAILABLE' ? section(key).data.length : section(key)?.state === 'FORBIDDEN' ? '无权限' : section(key)?.state === 'ERROR' ? '读取失败' : '待接入'
</script>
<template>
  <section class="workbench">
    <header class="workbench-heading"><div><p class="workbench-eyebrow">现场安全 / SAFETY OVERVIEW</p><h1>安全运行总览</h1><p>{{ context.data?.sites.find(s => s.siteId === siteId)?.name || '请选择授权厂站' }} · {{ user.user?.nickName }}</p></div><button class="event-button" :disabled="!authorized || result.state === 'LOADING'" @click="reload"><AppIcon name="Refresh" :size="16" /> 刷新概况</button></header>
    <p class="workbench-note">{{ result.data?.source === 'MOCK' ? '服务未接入 · 本地工作空间 · 数据在页面内共享，刷新恢复初始状态。详细操作进入对应工作区。' : '概况来源待接入，不以设备在线数代替当班人数。' }}</p>
    <DataState v-if="context.state === 'ERROR'" state="ERROR" message="厂站读取失败" retry @retry="context.load(true)" />
    <DataState v-else-if="!authorized" :state="context.state === 'LOADING' ? 'LOADING' : 'NOT_INTEGRATED'" :message="siteId && context.state === 'READY' ? '该厂站不在当前授权范围' : '请选择已授权厂站，厂站来源未接入时不显示业务数量'" />
    <DataState v-else-if="result.state !== 'READY'" :state="result.state" :message="result.error?.message" :retry="!!result.error" @retry="reload" />
    <template v-else>
      <section class="command-hero"><div class="command-hero-copy"><p class="v3-eyebrow">人 · 装备 · 作业</p><h2>看见现场，<br /><span>守护每一程。</span></h2><p>人、装备与作业协同，让安全管理从看得见，到管得住。</p><router-link :to="{ path: '/personnel', query: { siteId } }">进入人员监护 <span aria-hidden="true">↗</span></router-link><small>无测量数据不计为健康正常，不生成健康评分。</small></div><figure><img :src="showcaseImage('hero')" alt="蓝调夕照下的变电站巡检示意场景" width="600" height="400" /><figcaption>AI 场景示意 · 非实时画面</figcaption></figure></section>
      <div class="workbench-metrics"><button v-for="m in metrics" :key="m.key" :data-tone="m.key" :disabled="section(m.key)?.state !== 'AVAILABLE'" @click="open(m.key)"><span class="metric-title"><AppIcon :name="{ duty: 'User', equipment: 'Checked', open: 'Warning', mine: 'Document' }[m.key]" />{{ m.title }}</span><strong>{{ count(m.key) }}</strong><small>{{ m.note }}</small><span class="metric-action">{{ section(m.key)?.state === 'AVAILABLE' ? '查看同口径明细 →' : section(m.key)?.message || '来源未开放' }}</span></button></div>
      <SceneGallery :site-id="siteId" /><div class="workbench-columns">
        <section v-for="block in [{ key: 'open', title: '重点关注', note: '展示未处理告警前 5 项，不推定风险等级。' }, { key: 'mine', title: '可处理告警', note: '按厂站处理权限展示，不要求先认领。' }]" :key="block.key" class="workbench-panel"><header><h2>{{ block.title }}</h2><button class="event-button" :disabled="section(block.key)?.state !== 'AVAILABLE'" @click="open(block.key)">查看全部</button></header><p class="workbench-note">{{ block.note }}</p><DataState v-if="section(block.key)?.state !== 'AVAILABLE'" :state="section(block.key)?.state" :message="section(block.key)?.message" /><p v-else-if="!section(block.key).data.length" class="workbench-empty">当前厂站此范围暂无未处理告警。</p><router-link v-for="e in (section(block.key)?.data || []).slice(0, 5)" :key="e.eventId" class="workbench-event" :to="eventTarget(e)"><div><strong>{{ e.title }}</strong><small>{{ e.deviceCode }} · {{ e.eventId }}</small></div><span>{{ alarmLabel(e) }} →</span></router-link><button v-if="block.key === 'open'" class="unknown-link" :disabled="section('unknown')?.state !== 'AVAILABLE'" @click="open('unknown')">处理状态未知：{{ count('unknown') }} · 单独查看，不计入未完成</button></section>
      </div>
      <section v-if="result.data?.collaboration" class="workbench-panel"><header><h2>协同提醒</h2><router-link :to="{ path: '/dispatch', query: { siteId } }">进入调度协同 →</router-link></header><p class="workbench-note">本地会话与告警处理独立；接通或结束不会自动完成事件。</p><DataState v-if="result.data.collaboration.state !== 'AVAILABLE'" :state="result.data.collaboration.state" /><template v-else><p v-if="!result.data.collaboration.data.length && !result.data.broadcasts.data.length">没有进行中的本地会话或待回执广播。</p><p v-for="s in result.data.collaboration.data" :key="s.id">{{ s.title }} · 明确本地会话就绪 {{ s.count }} / {{ s.total }} 个对象</p><p v-for="b in result.data.broadcasts.data" :key="b.id">{{ b.title }} · {{ b.count }} 个对象待回执</p></template></section>
      <section class="workbench-panel"><header><h2>统计与口径</h2><router-link :to="{ path: '/statistics', query: { siteId } }">查看统计分析与导出 →</router-link></header><p class="workbench-note">当前快照与历史区间分开；装备领用率排除未知及冲突，告警处理量以处理时间为准。不提供健康评分，不将设备在线解释为人员健康或视频可用。</p></section>
      <section v-if="result.data?.works" class="workbench-panel"><header><h2>作业监护摘要</h2><router-link :to="{ path: '/supervision', query: { siteId } }">查看全部作业 →</router-link></header><DataState v-if="result.data.works.state !== 'AVAILABLE'" :state="result.data.works.state" :message="result.data.works.message" /><p v-else-if="!result.data.works.data.length">当前厂站没有作业。</p><router-link v-for="w in (result.data.works.data || []).slice(0, 5)" :key="w.workId" class="workbench-event" :to="{ path: '/supervision/' + w.workId, query: { siteId } }"><strong>{{ w.name }}</strong><span>{{ { PENDING: '待开始', ACTIVE: '监护中', PAUSED: '暂停', ENDED: '已结束' }[w.monitorState] }} · {{ w.participantCount }} 人 · {{ w.openEventCount ?? '未知' }} 件未处理告警</span></router-link></section>
      <section class="workbench-panel"><header><h2>快捷入口</h2><span>进入工作区，不启动设备连接</span></header><div class="workbench-shortcuts"><router-link v-for="item in [{ path: '/personnel', title: '查看当班人员' }, { path: '/location', query: { tab: 'live' }, title: '查看位置快照' }, { path: '/video', title: '查看视频设备' }, { path: '/alarms', title: '查看告警事件' }, { path: '/materials', title: '查询现场资料' }]" :key="item.path" :to="workspaceTarget(item, siteId)">{{ item.title }} →</router-link></div></section>
    </template>
    <el-dialog class="v3-metric-dialog" :model-value="!!drill" :title="titles[drill] || '明细'" width="min(900px, 92vw)" @close="drill = ''"><p>当前厂站 · 共 {{ rows.length }} 条 · 与安全总览指标使用同一份数据</p><div class="workbench-drill"><table><thead><tr><th>名称 / 标识</th><th>状态或类型</th><th>查看</th></tr></thead><tbody><tr v-for="item in visibleRows" :key="item.eventId || item.personId || item.deviceId"><td>{{ item.name || item.title }}<small>{{ item.personId || item.deviceCode || item.eventId }}</small></td><td>{{ item.eventId ? alarmLabel(item) : item.type ? { HELMET: '安全帽', BELT: '安全带', WATCH: '手表' }[item.type] : '名册当班' }}</td><td><router-link v-if="item.eventId" :to="eventTarget(item)" @click="drill = ''">查看告警 →</router-link><router-link v-else-if="item.personId" :to="{ path: '/personnel/' + item.personId, query: { siteId, returnTo: '/overview?siteId=' + siteId } }" @click="drill = ''">查看人员 →</router-link><router-link v-else :to="{ path: '/equipment/' + item.deviceId, query: { siteId } }" @click="drill = ''">查看装备 →</router-link></td></tr></tbody></table></div><p v-if="!rows.length">当前范围暂无记录。</p><AppPagination :current-page="page" :page-size="20" :total="rows.length" @current-change="page = $event" /></el-dialog>
  </section>
</template>
<style scoped>
.workbench { display:grid; gap:20px; color:var(--text-primary) }
.workbench-heading,.workbench-panel header { display:flex; align-items:center; justify-content:space-between; gap:16px }
h1 { font-size:28px } h2 { font-size:19px } .workbench-eyebrow { color:var(--cyan); font-size:13px; letter-spacing:2px }
.workbench-note,.workbench-heading p,.workbench-panel header>span { color:var(--text-secondary); font-size:13px }
.workbench-metrics { display:grid; grid-template-columns:repeat(4,minmax(0,1fr)); gap:16px }
.workbench-metrics button { display:grid; text-align:left; gap:8px; padding:20px; background:var(--panel-bg); border:1px solid var(--border); color:var(--text-primary); border-radius:5px }
.workbench-metrics button:hover:not(:disabled) { border-color:var(--cyan) } .workbench-metrics strong { font:600 34px/1.3 Consolas,monospace } small { display:block; color:var(--text-secondary); font-size:12px; overflow-wrap:anywhere } .metric-action { color:var(--cyan); font-size:12px }
.workbench-columns { display:grid; grid-template-columns:1.15fr 1fr; gap:20px }.workbench-panel { min-width:0; padding:20px; background:var(--panel-bg); border:1px solid var(--border); border-radius:5px }.workbench-panel header { margin-bottom:12px }
.workbench-event { display:flex; justify-content:space-between; align-items:center; gap:16px; padding:13px 0; border-bottom:1px solid var(--border-soft) }.workbench-event div { min-width:0; overflow-wrap:anywhere }.workbench-event>span { color:var(--cyan); font-size:13px; flex-shrink:0 }.workbench-event:hover { background:var(--input-bg) }.workbench-empty { padding:36px 0; color:var(--text-secondary) }
.unknown-link { margin-top:16px; background:transparent; border:0; color:var(--text-secondary); text-align:left; padding:8px 0 }.workbench-shortcuts { display:flex; gap:12px; flex-wrap:wrap }.workbench-shortcuts a { border:1px solid var(--border); padding:12px 18px; color:var(--cyan) }.workbench-drill { max-height:52vh; overflow:auto; margin:16px 0 } table { width:100%; border-collapse:collapse } td,th { padding:12px; border-bottom:1px solid var(--border); text-align:left; overflow-wrap:anywhere } td a { color:var(--cyan) }
@media(max-width:1100px) { .workbench-metrics { grid-template-columns:repeat(2,minmax(0,1fr)) }.workbench-columns { grid-template-columns:1fr } }
</style>
