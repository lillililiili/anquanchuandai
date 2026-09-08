<template>
  <header class="module-header" :class="{ 'module-header--compact': compact }">
    <div class="module-header__copy">
      <h1>{{ title || content.title }}</h1>
      <p>{{ description || content.description }}</p>
    </div>
    <div v-if="$slots.default" class="module-header__actions"><slot /></div>
    <img v-if="!imageFailed" alt="" aria-hidden="true" height="144" :src="image || content.image" width="280" @error="imageFailed = true" />
  </header>
</template>

<script setup>
import { computed, ref, watch } from 'vue'
import { moduleVisuals } from '@/config/visuals'
const props = defineProps({ module: { type: String, default: 'system' }, title: String, description: String, image: String, compact: Boolean })
const content = computed(() => moduleVisuals[props.module] || moduleVisuals.system)
const imageFailed = ref(false)
watch(() => [props.module, props.image], () => { imageFailed.value = false })
</script>

<style scoped>
.module-header { position: relative; isolation: isolate; display: flex; align-items: center; gap: 20px; min-height: 104px; flex-shrink: 0; margin-bottom: 20px; padding: 22px 28px; overflow: hidden; border: 1px solid var(--border-color); border-radius: 12px; background: #fff; }
.module-header__copy { position: relative; z-index: 1; max-width: calc(100% - 190px); }
.module-header h1 { margin: 0; color: var(--text-primary); font-size: 23px; font-weight: 650; line-height: 1.4; }
.module-header p { margin: 7px 0 0; color: var(--text-secondary); font-size: 13px; line-height: 1.6; }
.module-header > img { position: absolute; z-index: -1; right: 0; top: 50%; width: 280px; height: 170px; object-fit: cover; transform: translateY(-50%); pointer-events: none; mask-image: linear-gradient(to right, transparent, #000 35%); }
.module-header__actions { position: relative; z-index: 1; margin-left: auto; }
.module-header--compact { min-height: 72px; padding: 12px 22px; margin-bottom: 12px; }
.module-header--compact h1 { font-size: 20px; }
.module-header--compact p { margin-top: 2px; font-size: 12px; }
.module-header--compact > img { width: 225px; height: 135px; }
@media (max-width: 640px) { .module-header { padding: 18px; min-height: 96px; } .module-header__copy { max-width: 100%; } .module-header h1 { font-size: 20px; } .module-header > img { opacity: .12; } }
</style>
