<script setup>
import { onMounted, onUnmounted, ref } from "vue";
import { mountScreen } from "./screen-runtime";

const root = ref(null);
let stop = () => {};

onMounted(() => {
  document.documentElement.classList.add("screen-mode");
  stop = mountScreen(root.value);
});

onUnmounted(() => {
  stop();
  document.documentElement.classList.remove("screen-mode");
});
</script>

<template>
  <div ref="root"></div>
</template>
