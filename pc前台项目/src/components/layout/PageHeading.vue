<script setup>
defineProps({
  title: { type: String, default: "" },
  subtitle: { type: String, default: "" },
});
</script>

<template>
  <div class="page-heading">
    <div>
      <h1><slot name="title">{{ title }}</slot></h1>
      <p v-if="subtitle || $slots.subtitle"><slot name="subtitle">{{ subtitle }}</slot></p>
    </div>
    <div class="heading-actions"><slot name="actions" /></div>
  </div>
</template>
