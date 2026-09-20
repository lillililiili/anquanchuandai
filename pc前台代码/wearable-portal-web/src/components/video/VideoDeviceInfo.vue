<script setup>
import { videoLabels } from '@/utils/video-contract'
import { formatTime } from '@/utils/portal-contract'
import DeviceProfile from '@/components/equipment/DeviceProfile.vue'
defineProps({ device: { type: Object, required: true } })
</script>
<template><div class="video-device-info"><h3>{{ device.name }}</h3><dl><dt>设备编号</dt><dd>{{ device.deviceCode || device.deviceId }}</dd><dt>装备类型</dt><dd>{{ videoLabels[device.type] }}</dd><dt>设备通信</dt><dd>{{ videoLabels[device.communication.state] }}</dd><dt>视频能力</dt><dd>{{ videoLabels[device.video.state] }} / {{ videoLabels[device.video.verification] }}</dd><dt>来源流状态</dt><dd>{{ videoLabels[device.streamState] }}</dd><dt>来源时间</dt><dd>{{ formatTime(device.sourceTime) === '—' ? '未知' : formatTime(device.sourceTime) }}{{ device.freshness === 'STALE' ? ' · 数据已过期' : '' }}</dd></dl><DeviceProfile v-if="device.profile" :device="device" compact /><p class="video-note">通信在线不代表视频可用；来源报告不代表本机正在播放。</p></div></template>
