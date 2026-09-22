<script setup>
defineOptions({ inheritAttrs: false });
defineProps({
  text: { type: String, default: "" },
});
</script>

<template>
  <p>{{ text }}</p>
</template>
