<script setup>
import { onMounted, onUnmounted, ref } from "vue";
import { mountScreen } from "./screen-runtime";
import PlantMap from "@/components/domain/PlantMap.vue";

const root = ref(null);
const mapTarget = ref(null);
let stop = () => {};

onMounted(() => {
  document.documentElement.classList.add("screen-mode");
  stop = mountScreen(root.value);
  mapTarget.value = root.value.querySelector("[data-screen-map]");
});

onUnmounted(() => {
  stop();
  document.documentElement.classList.remove("screen-mode");
});
</script>

<template>
  <div ref="root"></div>
  <Teleport v-if="mapTarget" :to="mapTarget">
    <PlantMap area-counts :markers="false" :fences="false" map-class="screen-plant-map" />
  </Teleport>
</template>
