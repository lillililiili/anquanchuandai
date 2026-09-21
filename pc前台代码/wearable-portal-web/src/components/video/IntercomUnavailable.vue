<script setup>
defineProps({ mode: { type: String, default: 'VOICE' } })
</script>
<template><button class="video-button" disabled title="通信服务未接入，暂不能发起通话">{{ mode === 'VIDEO' ? '发起音视频通话' : '发起对讲' }}</button></template>
