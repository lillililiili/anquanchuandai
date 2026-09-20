<template>
  <div v-if="loading" aria-live="polite" class="query-state"><Loading class="loading-icon" aria-hidden="true" />正在读取本地数据…</div>
  <div v-else-if="error" class="query-state error" role="alert">
    <img :src="stateArt" alt="" width="118" height="94" class="state-art" />
    <strong>{{ error.code === 403 ? '无权限' : '读取失败' }}</strong>
    <p>{{ error.message }}</p><small>{{ error.errorCode }} · {{ error.requestId }}</small>
    <button class="button" @click="$emit('retry')">重新读取</button>
  </div>
  <div v-else-if="data?.availability === 'NOT_CONNECTED'" class="query-state"><img :src="stateArt" alt="" width="118" height="94" class="state-art" /><strong>未接入</strong><p>{{ data.reason }}</p></div>
  <slot v-else />
</template>
<script setup>
import { Loading } from '@element-plus/icons-vue'
import stateArt from '../assets/visual/state-empty.webp'
defineProps({ loading: Boolean, error: Object, data: Object })
defineEmits(['retry'])
</script>
