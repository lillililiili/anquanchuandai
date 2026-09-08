<template>
  <div class="branded-empty" :class="{ 'branded-empty--compact': compact }">
    <img v-if="!imageFailed" alt="" height="112" loading="lazy" :src="image" width="144" @error="imageFailed = true" />
    <p>{{ description }}</p>
    <span v-if="hint">{{ hint }}</span>
    <slot />
  </div>
</template>

<script setup>
import { computed, ref } from 'vue'
const props = defineProps({ description: { type: String, default: '暂无记录' }, hint: String, device: Boolean, compact: Boolean })
const imageFailed = ref(false)
const image = computed(() => `${import.meta.env.BASE_URL}visuals/empty-${props.device ? 'device' : 'records'}.webp`)
</script>

<style scoped>
.branded-empty { display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 8px; padding: 22px 12px; color: var(--text-secondary); line-height: 1.5; }
.branded-empty img { display: block; width: 144px; height: 112px; object-fit: cover; border-radius: 14px; mix-blend-mode: multiply; }
.branded-empty p { margin: 0; font-size: 13px; color: var(--text-secondary); }
.branded-empty > span { color: var(--text-muted); font-size: 12px; }
.branded-empty--compact { padding: 8px; gap: 4px; }
.branded-empty--compact img { width: 96px; height: 72px; }
</style>
