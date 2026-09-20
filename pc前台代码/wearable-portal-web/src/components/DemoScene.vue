<script setup>
import { computed } from 'vue'
import { sceneFor } from '@/utils/demo-scenes'
const props = defineProps({ identity: { type: String, default: '' }, label: { type: String, default: 'AI 场景示意 · 非实时画面' } })
const scene = computed(() => sceneFor(props.identity))
</script>
<template><figure class="demo-scene"><img :src="scene.image" :alt="scene.title + '概念示意图片'" loading="lazy" width="640" height="360" /><figcaption>{{ label }}</figcaption></figure></template>
