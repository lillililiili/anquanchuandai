<script setup>
import DemoScene from '@/components/DemoScene.vue'
import { ref, onMounted, onBeforeUnmount } from 'vue'
import { createVideoPlayer, playerLabels } from '@/utils/video-player'
import { closedMediaProvider } from '@/utils/media-provider'
import { createMediaAdapter } from '@/utils/video-adapters'
import AppIcon from '@/components/AppIcon.vue'
import { formatTime } from '@/utils/portal-contract'
const props = defineProps({ device: { type: Object, default: null }, compact: Boolean })
const panel = ref(null), media = ref(null), snapshot = ref({ state: 'NOT_INTEGRATED', lastDisplayedAt: null, sourceTime: null }), fullscreenError = ref('')
let player
onMounted(() => { if (props.device?.video?.state === 'UNSUPPORTED') snapshot.value.state = 'UNSUPPORTED'; player = createVideoPlayer({ media: media.value, provider: closedMediaProvider, createAdapter: createMediaAdapter, onChange: value => { snapshot.value = value } }) })
onBeforeUnmount(() => player?.destroy())
async function fullscreen() { fullscreenError.value = await player.fullscreen(panel.value) ? '' : '浏览器拒绝全屏，请使用窗口查看' }
</script>
<template>
  <section ref="panel" class="video-player" :class="{ compact }" aria-label="监看面板">
    <DemoScene v-if="!snapshot.lastDisplayedAt" :identity="device?.deviceId || device?.name" />
      <video ref="media" muted playsinline preload="none" aria-label="监看画面" />
    <header><span>{{ device?.name || '未分配' }}</span><span class="video-tag">{{ device ? playerLabels[snapshot.state] : '未分配槽位' }}</span></header>
    <div class="video-screen-message"><AppIcon name="VideoCamera" :size="compact ? 28 : 48" /><strong>{{ device ? '真实媒体访问未开放' : '未分配监看设备' }}</strong><span v-if="device && !compact">{{ device.video?.verification === 'VERIFIED' ? '能力已验证，媒体授权仍未开放' : '视频能力待验证，不自动拉流' }}</span></div>
    <footer v-if="device"><small v-if="!compact">设备画面源时间：{{ formatTime(snapshot.sourceTime) === '—' ? '未知' : formatTime(snapshot.sourceTime) }}<br>本机最后显示：{{ snapshot.lastDisplayedAt ? formatTime(snapshot.lastDisplayedAt) : '尚无画面' }}</small><button type="button" class="video-button" aria-label="全屏监看面板" @click="fullscreen">全屏</button></footer>
    <p v-if="fullscreenError" role="status">{{ fullscreenError }}</p>
  </section>
</template>
