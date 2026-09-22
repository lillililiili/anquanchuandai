<script setup>
defineProps({
  color: { type: String, default: "blue" },
});
</script>

<template>
  <span :class="['tag', color]"><slot /></span>
</template>
