<script setup>
import { onMounted, onUnmounted, watch } from "vue";
import { useRoute } from "vue-router";
import Topbar from "./Topbar.vue";
import { db } from "@/mock/runtime";
import { session } from "@/stores/session";
import DeviceSessionBar from '@/components/domain/DeviceSessionBar.vue';

const route = useRoute();
let videoTimer;
let trackTimer;

function restartTrack() {
  clearInterval(trackTimer);
  if (route.name === "tracks" && session.trackPlaying) {
    trackTimer = setInterval(() => {
      session.trackIndex += 1;
      if (session.trackIndex >= session.trackPoints.length) {
        session.trackIndex = Math.max(0, session.trackPoints.length - 1);
        session.trackPlaying = false;
      }
    }, 1500 / (Number(session.trackSpeed) || 1));
  }
}

onMounted(() => {
  videoTimer = setInterval(() => {
    if (session.playing && (route.name === "single" || route.name === "work")) session.videoTick += 1;
  }, 1000);
  restartTrack();
});

watch(() => [route.name, session.trackPlaying, session.trackSpeed, session.trackPoints.length], restartTrack);

onUnmounted(() => {
  clearInterval(videoTimer);
  clearInterval(trackTimer);
});
</script>

<template>
  <header class="portal-header">
    <Topbar />
  </header>
  <div class="portal-workspace">
    <DeviceSessionBar />
    <p v-if="db.demoMode" class="note" role="status">演示模式：示例画面、轨迹和状态仅用于界面演示。</p>
    <main id="main" :class="['main', route.name + '-page']"><slot /></main>
  </div>
</template>
