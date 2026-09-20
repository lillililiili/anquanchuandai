<script setup>
import { computed, reactive, watch } from 'vue'
import { getVitals, simulatedVitals } from '@/api/vitals'
import { vitalMetrics, vitalStates, vitalValue } from '@/utils/vitals-contract'
import { formatTime } from '@/utils/portal-contract'
import { usePortalQuery } from '@/composables/usePortalQuery'
import { useBusinessRevision } from '@/composables/useBusinessRevision'
import { useContextStore } from '@/store/context'
import { useUserStore } from '@/store/user'
const props = defineProps({ siteId: String, personId: String, deviceId: String, compact: Boolean, showcase: Boolean })
const context = useContextStore(), user = useUserStore(), query = reactive(usePortalQuery())
const state = computed(() => query.state === 'LOADING' ? 'LOADING' : query.error ? query.state === 'FORBIDDEN' ? 'FORBIDDEN' : 'UNAVAILABLE' : query.data?.state || 'NOT_INTEGRATED')
const cards = computed(() => Object.entries(vitalMetrics).map(([key, spec]) => ({ key, ...spec, reading: query.data?.items.find(i => i.metric === key) })))
function reload() {
  if (!user.token || context.state !== 'READY' || context.selectedSiteId !== props.siteId || !context.data?.sites.some(s => s.siteId === props.siteId) || (!props.personId && !props.deviceId)) return query.clear()
  query.run(signal => getVitals({ siteId: props.siteId, ...(props.personId ? { personId: props.personId } : { deviceId: props.deviceId }) }, signal))
}
watch(() => [props.siteId, props.personId, props.deviceId, user.token, context.state, context.selectedSiteId, context.data], reload, { immediate: true })
useBusinessRevision(['people', 'equipment'], reload)
</script>
<template>
  <section class="vitals-panel" :class="{ 'vitals-compact': compact, 'vitals-showcase': showcase }" aria-label="生命体征">
    <header class="vitals-header"><div><span class="vitals-eyebrow">{{ simulatedVitals ? '预置观测 · 非诊断' : '生命体征' }}</span><h2>生命体征<span v-if="simulatedVitals">（本地）</span></h2></div><span class="vitals-status" role="status">{{ vitalStates[state] }}</span></header>
    <p class="vitals-notice">{{ simulatedVitals ? '预置体征，非实时测量；手表能力待确认' : '真实体征来源未接入；手表能力待确认' }}</p>
    <div class="vitals-body">
      <div v-if="!compact" class="vitals-human" aria-hidden="true">
        <img v-if="showcase" class="v3-human-image" src="@/assets/images/v3-human.webp" alt="" width="400" height="600" />
        <svg v-else viewBox="0 0 240 390" role="presentation" focusable="false">
          <ellipse cx="120" cy="360" rx="99" ry="18" class="human-ring outer" /><ellipse cx="120" cy="360" rx="72" ry="12" class="human-ring" /><ellipse cx="120" cy="360" rx="44" ry="6" class="human-base" />
          <g class="human-outline"><path d="M120 24 C102 24 96 36 97 49 C97 60 103 69 108 73 L108 85 L89 91 C77 94 72 103 68 116 L61 150 L53 185 L48 210 L51 224 L58 225 L62 208 L63 189 L75 158 L86 129 L91 166 L87 187 L91 219 L96 252 L96 278 L98 307 L96 343 L88 354 L88 361 L111 361 L115 352 L114 312 L119 270 L120 237 L121 270 L126 312 L125 352 L129 361 L152 361 L152 354 L144 343 L142 307 L144 278 L144 252 L149 219 L153 187 L149 166 L154 129 L165 158 L177 189 L178 208 L182 225 L189 224 L192 210 L187 185 L179 150 L172 116 C168 103 163 94 151 91 L132 85 L132 73 C137 69 143 60 143 49 C144 36 138 24 120 24 Z" /></g>
          <g class="human-detail"><path d="M108 85 L120 100 L132 85 M89 99 Q102 92 116 106 L116 135 Q100 141 86 128 M151 99 Q138 92 124 106 L124 135 Q140 141 154 128 M120 102 L120 191 M95 145 Q104 150 115 146 M125 146 Q136 150 145 145 M95 156 Q104 161 115 157 M125 157 Q136 161 145 156 M95 168 Q104 173 115 169 M125 169 Q136 173 145 168 M95 183 L112 197 L120 210 L128 197 L145 183 M95 199 L107 222 L109 264 L103 296 L105 340 M145 199 L133 222 L131 264 L137 296 L135 340 M82 108 L76 143 L66 178 M158 108 L164 143 L174 178" /><ellipse cx="105" cy="278" rx="6" ry="9" /><ellipse cx="135" cy="278" rx="6" ry="9" /></g>
          <g class="human-guides"><path d="M83 116 H38 L24 103 H4 M157 116 H202 L216 103 H236 M90 192 H38 L24 213 H4 M150 192 H202 L216 213 H236" /><circle cx="83" cy="116" r="3" /><circle cx="157" cy="116" r="3" /><circle cx="90" cy="192" r="3" /><circle cx="150" cy="192" r="3" /></g>
        </svg><span>人体示意 · 非传感器位置图</span>
      </div>
      <article v-for="card in cards" :key="card.key" class="vital-card" :class="'vital-' + card.key" :data-metric="card.key">
        <h3>{{ card.label }}</h3><p class="vital-number"><strong>{{ vitalValue(card.reading) }}</strong><span>{{ card.unit }}</span></p>
        <p class="vital-quality">{{ !card.reading ? vitalStates[state] === '预置观测' ? '指标未知' : vitalStates[state] : card.reading.value === null ? '指标缺失' : card.reading.freshness === 'STALE' ? '历史读数 / 已过期' : card.reading.freshness === 'UNKNOWN' ? '源时间未知' : '本地样例 · 非实时测量' }}</p>
        <small v-if="!compact">观测：{{ formatTime(card.reading?.sourceTime) === '—' ? '未知' : formatTime(card.reading.sourceTime) }}</small>
        <small v-if="!compact && card.reading">接收：{{ formatTime(card.reading.receivedAt) }}</small>
      </article>
    </div>
    <footer class="vitals-footer"><p v-if="query.error" role="alert">{{ query.error.message }} <button type="button" @click="reload">重试体征查询</button></p><template v-else><p>{{ query.data?.reason || '各指标独立表达缺失和时效；不生成健康结论或自动告警。' }}</p><p v-if="query.data?.items.length">来源：{{ query.data.items[0].deviceCode }} · 观测归属：{{ query.data.items[0].personName }}（预置记录）</p></template><router-link v-if="compact && personId" :to="{ path: '/personnel/' + personId, query: { siteId } }">查看人形体征详情 →</router-link></footer>
  </section>
</template>
<style scoped>
.vitals-panel { --vital-ink: #e8f7ff; --vital-muted: #abcddd; --vital-cyan: #63dcff; color: var(--vital-ink); background: radial-gradient(ellipse at 50% 60%, #103e58 0, #08283d 42%, #062235 75%); border: 1px solid #31596e; padding: 22px; min-width: 0; container-type: inline-size; }
.vitals-header { display: flex; justify-content: space-between; gap: 16px; align-items: center; }
.vitals-eyebrow { font-size: 12px; color: var(--vital-cyan); letter-spacing: 2px; }
.vitals-header h2 { font-size: 20px; margin: 6px 0; }
.vitals-header h2 span { font-size: 14px; font-weight: 400; }
.vitals-status { border: 1px solid #42718c; color: #c5eaff; padding: 5px 10px; font-size: 12px; }
.vitals-notice { font-size: 13px; color: #e5ce91; margin: 10px 0 18px; }
.vitals-body { display: grid; grid-template-columns: minmax(140px, 1fr) minmax(170px, .95fr) minmax(140px, 1fr); grid-template-rows: 1fr 1fr; gap: 16px 8px; align-items: center; }
.vitals-human { grid-column: 2; grid-row: 1 / 3; text-align: center; min-width: 0; }
.vitals-human svg { width: 100%; max-height: 360px; overflow: visible; }
.vitals-human > span { color: var(--vital-muted); font-size: 11px; }
.human-outline { fill: #0a405a; stroke: #79e4ff; stroke-width: 1.7; filter: drop-shadow(0 0 5px #29b9ed); }
.human-detail { fill: none; stroke: #3cb9df; stroke-width: 1; opacity: .8; }
.human-guides { stroke: #3e90ac; fill: none; stroke-width: .8; }.human-guides circle { fill: #7ceaff; }
.human-ring { fill: #0c587b; fill-opacity: .35; stroke: #54d7fa; stroke-width: 1; }
.human-ring.outer { fill: none; opacity: .5; }
.human-base { fill: #62dfff; opacity: .5; }
.vital-card { background: linear-gradient(120deg, #103b53d9, #0b2c41b3); border: 1px solid #376077; border-left: 2px solid #60d7f5; padding: 14px; min-width: 0; overflow-wrap: anywhere; }
.vital-heartRate { grid-column: 1; grid-row: 1; }.vital-oxygen { grid-column: 1; grid-row: 2; }.vital-temperature { grid-column: 3; grid-row: 1; }.vital-bloodPressure { grid-column: 3; grid-row: 2; }
.vital-card h3 { font-size: 14px; font-weight: 500; margin: 0; color: #d3eaf6; }
.vital-number { display: flex; flex-wrap: wrap; align-items: baseline; gap: 8px; margin: 8px 0; }
.vital-number strong { font-size: clamp(22px, 3cqw, 34px); font-family: Consolas, monospace; font-weight: 500; color: #a2edff; }
.vital-number span, .vital-quality, .vital-card small { font-size: 12px; color: var(--vital-muted); }
.vital-quality { margin: 6px 0; }.vital-card small { display: block; line-height: 1.7; }
.vitals-footer { border-top: 1px solid #31546a; margin-top: 20px; padding-top: 10px; font-size: 12px; color: var(--vital-muted); overflow-wrap: anywhere; }
.vitals-footer button, .vitals-footer a { color: #86e1ff; }.vitals-footer button { background: transparent; border: 1px solid #46748b; cursor: pointer; padding: 5px 10px; }
.vitals-compact { padding: 12px; }.vitals-compact .vitals-header { flex-wrap: wrap; }.vitals-compact .vitals-body { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; }.vitals-compact .vital-card { grid-column: auto; grid-row: auto; padding: 10px; }.vitals-compact .vital-number strong { font-size: 20px; }
@container (max-width: 580px) { .vitals-body { grid-template-columns: 1fr 1fr; }.vitals-human { grid-column: 1 / 3; grid-row: 1; }.vitals-human svg { max-height: 290px; }.vital-heartRate, .vital-oxygen, .vital-temperature, .vital-bloodPressure { grid-column: auto; grid-row: auto; }.vitals-header { flex-wrap: wrap; } }
@media (prefers-reduced-motion: reduce) { .human-outline { filter: none; } }
</style>
