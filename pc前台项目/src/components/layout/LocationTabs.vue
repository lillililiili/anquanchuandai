<script setup>
import { useRoute } from "vue-router";

const route = useRoute();
const tabs = [
  ["location", "实时定位"],
  ["tracks", "历史轨迹"],
  ["fences", "电子围栏"],
];
</script>

<template>
  <div class="tabs">
    <a v-for="[id, label] in tabs" :key="id" :href="'#/' + id" :class="route.name === id ? 'active' : ''">{{ label }}</a>
  </div>
</template>
