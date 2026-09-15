<template>
  <header class="module-header" :class="{ 'module-header--compact': compact }">
    <span class="module-header__rail" aria-hidden="true"></span>
    <div class="module-header__copy">
      <h1>{{ title || content.title }}</h1>
      <p>{{ description || content.description }}</p>
    </div>
    <div v-if="$slots.default" class="module-header__actions"><slot /></div>
  </header>
</template>

<script setup>
import { computed } from 'vue'
import { moduleVisuals } from '@/config/visuals'
const props = defineProps({ module: { type: String, default: 'system' }, title: String, description: String, image: String, compact: Boolean })
const content = computed(() => moduleVisuals[props.module] || moduleVisuals.system)
</script>

<style scoped>
.module-header { position: relative; display: flex; align-items: center; gap: 16px; min-height: 70px; margin-bottom: 14px; padding: 14px 18px; border: 1px solid var(--border-color); border-radius: 8px; background: #fff; box-shadow: 0 1px 2px rgba(23, 43, 69, .04); }
.module-header__rail { align-self: stretch; width: 3px; border-radius: 2px; background: linear-gradient(180deg, var(--brand-primary), #d97706); }
.module-header__copy { min-width: 0; }
.module-header h1 { margin: 0; color: var(--text-primary); font-size: 20px; font-weight: 650; line-height: 1.35; }
.module-header p { margin: 3px 0 0; color: var(--text-secondary); font-size: 13px; line-height: 1.45; }
.module-header__actions { margin-left: auto; }
.module-header--compact { min-height: 60px; padding-block: 10px; }
.module-header--compact h1 { font-size: 18px; }
@media (max-width: 640px) { .module-header { align-items: flex-start; padding: 12px; } .module-header__actions { margin-left: 0; } }
</style>
