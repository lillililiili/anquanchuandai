<script setup>
import { showcaseImage } from '@/utils/demo-scenes'
import { capabilityNames, profileLabels, capabilityDecision } from '@/utils/device-profile'
import { formatTime } from '@/utils/portal-contract'
defineProps({ device: { type: Object, required: true }, compact: Boolean })
</script>
<template>
  <section class="device-profile" aria-label="设备型号与能力">
    <figure v-if="!compact" class="equipment-showcase"><img :src="showcaseImage('equipment')" alt="智能安全帽、安全带、手表概念装备展示" /><figcaption>概念装备展示 · 非厂家实物</figcaption></figure><h3>{{ device.model || '型号待确认' }}</h3>
    <p v-if="!device.profile">实例配置及厂家能力待确认</p>
    <template v-else>
      <p class="profile-disclaimer">需求本地 · 型号/装配为合成配置 · 真机未验证</p>
      <p v-if="device.type === 'HELMET'">隐私报告：{{ { ON: '本地已开启', OFF: '本地关闭', UNKNOWN: '未知' }[device.profile.privacy] }}；不提供设备控制</p>
      <dl v-if="device.profile.observations.length && !compact" class="profile-readings"><template v-for="o in device.profile.observations" :key="o.label"><dt>{{ o.label }}</dt><dd>{{ o.value ?? '未知' }}<small>{{ o.freshness === 'STALE' ? '历史读数 / 已过期' : o.freshness === 'UNKNOWN' ? '时效未知' : '预置数据' }} · {{ formatTime(o.sourceTime) }}</small></dd></template></dl>
      <p v-if="device.type === 'BELT'">锁扣闭合不证明挂点可靠，单钩不自动等于违规；厂家协议待确认。</p>
      <details><summary>资料声明、本地配置与禁用原因</summary><div class="profile-capabilities"><article v-for="(name, key) in capabilityNames" :key="key"><strong>{{ name }}</strong><span>{{ profileLabels[device.profile.capabilities[key].declaration] }} · {{ profileLabels[device.profile.capabilities[key].installation] }}</span><small>{{ profileLabels[device.profile.capabilities[key].integration] }} · 真机未验证</small><span>{{ capabilityDecision(device, key).reason }}</span><small>{{ device.profile.capabilities[key].evidence }}</small></article></div></details>
    </template>
  </section>
</template>
<style scoped>
.device-profile { min-width: 0; overflow-wrap: anywhere; color: #d4e9f6; font-size: 13px; line-height: 1.65; }
.device-profile h3 { color: #eaf8ff; margin: 0 0 8px; }
.profile-disclaimer { color: #afdcef; }
.profile-readings { display: grid; grid-template-columns: minmax(100px, 1fr) 1.5fr; gap: 8px 12px; }
.profile-readings dd { margin: 0; }
.profile-readings small { display: block; color: #a9cadd; }
summary { cursor: pointer; padding: 10px 0; color: #76dbff; }
summary:focus-visible { outline: 2px solid #76dbff; outline-offset: 3px; }
.profile-capabilities { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 10px; }
.profile-capabilities article { padding: 12px; border: 1px solid #31546a; background: #07263a; display: grid; gap: 4px; }
.profile-capabilities small { color: #b0cadb; }
</style>
