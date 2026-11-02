<template>
  <section class="panel device-feature-panel" aria-label="设备功能与验收状态">
    <h2>设备功能与验收状态</h2>
    <p class="muted feature-intro">功能状态以当前设备的接入和验收记录为准。实时操作仍需有效领用、设备在线及操作权限。</p>
    <template v-if="rows.length">
      <table class="feature-table">
        <caption class="sr-only">各项设备功能的支持范围、接入、验收及当前可用状态</caption>
        <colgroup><col class="feature-name-column"><col><col><col><col class="feature-availability-column"></colgroup>
        <thead><tr><th scope="col">功能</th><th scope="col">设备支持</th><th scope="col">接入状态</th><th scope="col">验收状态</th><th scope="col">当前可用性</th></tr></thead>
        <tbody><tr v-for="row in rows" :key="row.key">
          <th scope="row">{{ row.label }}<small v-if="row.code">{{ row.code }}</small></th>
          <td v-for="field in fields" :key="field.key"><span class="feature-status" :data-tone="row[field.key].tone">{{ row[field.key].label }}</span><small v-if="field.key === 'availability' && row.reason">{{ row.reason }}</small></td>
        </tr></tbody>
      </table>
      <ul class="feature-cards" aria-label="设备功能状态列表">
        <li v-for="row in rows" :key="row.key">
          <h3>{{ row.label }}<small v-if="row.code">{{ row.code }}</small></h3>
          <dl><template v-for="field in fields" :key="field.key"><dt>{{ field.label }}</dt><dd><span class="feature-status" :data-tone="row[field.key].tone">{{ row[field.key].label }}</span><small v-if="field.key === 'availability' && row.reason">{{ row.reason }}</small></dd></template></dl>
        </li>
      </ul>
    </template>
    <p v-else class="query-state">尚未提供本设备的功能与验收记录。</p>
  </section>
</template>

<script setup>
import { computed } from 'vue'
import { deviceFeatureRows } from '../deviceFeaturePresentation'
const props = defineProps({ device: { type: Object, required: true } })
const rows = computed(() => deviceFeatureRows(props.device))
const fields = [{ key: 'support', label: '设备支持' }, { key: 'integration', label: '接入状态' }, { key: 'verification', label: '验收状态' }, { key: 'availability', label: '当前可用性' }]
</script>

<style scoped>
.device-feature-panel { margin-top: 20px; }
.feature-intro { margin: 0 0 16px; line-height: 1.7; }
.feature-table { width: 100%; border-collapse: collapse; table-layout: fixed; }
.feature-name-column { width: 20%; }
.feature-availability-column { width: 28%; }
.feature-table th, .feature-table td { padding: 12px 16px; text-align: left; vertical-align: top; border-bottom: 1px solid var(--line); overflow-wrap: anywhere; }
.feature-table thead th { background: var(--table-head); font-weight: 600; }
.feature-table tbody th { font-weight: 500; }
.feature-table tbody tr:nth-child(even) { background: var(--theme-row-even); }
.feature-table tbody tr:last-child > * { border-bottom: 0; }
.feature-status { display: inline-block; color: var(--muted); line-height: 1.7; }
.feature-status[data-tone='ready'] { color: var(--success); }
.feature-status[data-tone='pending'] { color: var(--orange); }
.device-feature-panel small { display: block; margin-top: 4px; color: var(--muted); font-size: 12px; line-height: 1.7; font-weight: 400; overflow-wrap: anywhere; }
.feature-cards { display: none; }
@media (max-width: 760px) {
  .feature-table { display: none; }
  .feature-cards { display: grid; gap: 12px; padding: 0; margin: 0; list-style: none; }
  .feature-cards li { padding: 16px; border: 1px solid var(--line); border-radius: var(--control-radius); min-width: 0; }
  .feature-cards h3 { margin: 0 0 12px; font-size: 15px; line-height: 1.6; }
  .feature-cards dl { display: grid; grid-template-columns: 6em minmax(0, 1fr); align-items: start; gap: 8px 16px; margin: 0; }
  .feature-cards dt { color: var(--muted); }
  .feature-cards dd { margin: 0; min-width: 0; overflow-wrap: anywhere; }
}
</style>
