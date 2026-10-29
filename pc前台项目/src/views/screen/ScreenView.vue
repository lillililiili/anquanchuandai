<script setup>
import { onMounted, onUnmounted, ref } from "vue";
import { mountScreen } from "./screen-runtime";
import PlantMap from "@/components/domain/PlantMap.vue";
import VideoFrame from "@/components/domain/VideoFrame.vue";

const root = ref(null);
const mapTarget = ref(null);
const videoTarget = ref(null);
const videos = ref([]);
let stop = () => {};

onMounted(() => {
  document.documentElement.classList.add("screen-mode");
  stop = mountScreen(root.value, { onVideos: people => { videos.value = people; } });
  mapTarget.value = root.value.querySelector("[data-screen-map]");
  videoTarget.value = root.value.querySelector("[data-screen-videos]");
});

onUnmounted(() => {
  stop();
  document.documentElement.classList.remove("screen-mode");
});
</script>

<template>
  <div ref="root"></div>
  <Teleport v-if="mapTarget" :to="mapTarget">
    <PlantMap always-show-people popup :fences="false" map-class="screen-plant-map" />
  </Teleport>
  <Teleport v-if="videoTarget" :to="videoTarget">
    <VideoFrame v-for="person in videos" :key="person.id" :person-id="person.id" preview show-name />
  </Teleport>
</template>

<style scoped>
:deep([data-screen-videos] .video-frame), :deep([data-screen-videos] .helmet-preview) { height:100%; min-height:0; aspect-ratio:auto; }
:deep([data-screen-videos] .live-video), :deep([data-screen-videos] .live-video video) { height:100%; min-height:0; max-height:100%; }
:deep([data-screen-videos] .preview-start) { height:100%; min-height:0; padding:8px 12px 38px; gap:6px; font-size:12px; }
:deep([data-screen-videos] .video-name) { font-size:12px; }
:deep([data-screen-videos] .live-label) { top:auto; bottom:32px; font-size:10px; padding:2px 5px; }
</style>
