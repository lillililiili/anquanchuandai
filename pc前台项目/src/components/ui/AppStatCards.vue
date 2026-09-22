<script setup>
import AppIcon from "./AppIcon.vue";

defineProps({
  items: { type: Array, default: () => [] },
  variant: { type: String, default: "" },
});
</script>

<template>
  <div :class="['stats', variant]">
    <div v-for="item in items" :key="item.label" class="stat">
      <AppIcon :name="item.icon" :color="item.color" />
      <div>
        <span>{{ item.label }}</span>
        <strong>{{ item.value }} <small>{{ item.unit }}</small></strong>
        <em v-if="item.detail">{{ item.detail }}</em>
      </div>
    </div>
  </div>
</template>
