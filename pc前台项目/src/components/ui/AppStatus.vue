<script setup>
defineProps({
  color: { type: String, default: "green" },
});
</script>

<template>
  <span :class="['status', color]"><b></b><slot /></span>
</template>
