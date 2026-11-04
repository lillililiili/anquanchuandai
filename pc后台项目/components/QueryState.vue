<template>
  <div v-if="loading" aria-live="polite" class="query-state"><Loading class="loading-icon" aria-hidden="true" />正在读取数据…</div>
  <div v-else-if="error" class="query-state error" role="alert">
    <img :src="stateArt" alt="" width="118" height="94" class="state-art" />
    <strong>{{ error.code === 403 ? '无权限' : '读取失败' }}</strong>
    <p>{{ error.message }}</p><small>{{ error.errorCode }} · {{ error.requestId }}</small>
    <button class="button" @click="$emit('retry')">重新读取</button>
  </div>
  <div v-else-if="data?.availability === 'NOT_CONNECTED'" class="query-state"><img :src="stateArt" alt="" width="118" height="94" class="state-art" /><strong>服务暂时不可用</strong><p>{{ featureUnavailableReason(data.reason) }}</p><button class="button" @click="$emit('retry')">重新读取</button></div>
  <slot v-else />
</template>
<script setup>
import { Loading } from '@ui-spec/element-icons'
import { featureUnavailableReason } from '../../shared/device-features.mjs'
import stateArt from '../assets/visual/state-empty.webp'
defineProps({ loading: Boolean, error: Object, data: Object })
defineEmits(['retry'])
</script>
