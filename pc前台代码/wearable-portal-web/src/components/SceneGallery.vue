<script setup>
import { scenes } from '@/utils/demo-scenes'
defineProps({ siteId: String })
</script>
<template>
  <section class="scene-gallery" aria-label="现场场景示意">
    <header><div><span class="v3-eyebrow">FIELD OPERATIONS</span><h2>走进每一个作业现场</h2></div><span class="scene-demo-label">AI 场景示意 · 非实时画面</span></header>
    <div class="scene-gallery-grid"><router-link v-for="scene in scenes" :key="scene.id" :to="{ path: scene.path, query: { siteId } }" class="scene-card"><img :src="scene.image" :alt="scene.title + '示意场景'" loading="lazy" width="640" height="360" /><div><span class="scene-card-action" aria-hidden="true">↗</span><h3>{{ scene.title }}</h3><p>{{ scene.description }}</p></div></router-link></div>
  </section>
</template>
