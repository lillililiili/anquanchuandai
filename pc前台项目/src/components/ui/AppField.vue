<script setup>
defineProps({
  label: { type: String, default: "" },
  vertical: Boolean,
});
</script>

<template>
  <label class="field" :class="{ vertical }">
    <span v-if="label || $slots.label"><slot name="label">{{ label }}</slot></span>
    <slot />
  </label>
</template>
