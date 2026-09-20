<script setup>
defineProps({ title: { type: String, required: true } })
</script>

<template>
  <section class="portal-panel" :aria-label="title">
    <header class="panel-heading"><h2>{{ title }}</h2><slot name="actions" /></header>
    <div class="panel-body"><slot /></div>
  </section>
</template>
