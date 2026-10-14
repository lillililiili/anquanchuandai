<script setup>
import { computed, useId, watchEffect } from 'vue'
import { icons, resolveIcon } from './icons'
const props = defineProps({ name: { type: String, required: true } })
const uid = useId().replaceAll(':', '-')
const name = computed(() => resolveIcon(props.name))
const icon = computed(() => icons[name.value])
if (import.meta.env.DEV) watchEffect(() => { if (!icon.value) console.warn(`Unmapped Sketch icon: ${props.name}`) })
// Each instance needs its own clip IDs (multiple icons can appear in dialogs).
const body = computed(() => icon.value?.body.replaceAll('clip-', `${uid}-clip-`) || '')
</script>
<template>
  <svg v-if="icon" class="ui-icon" :data-source-icon="name" :viewBox="icon.viewBox" aria-hidden="true" focusable="false" v-html="body" />
</template>
