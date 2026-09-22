<script setup>
import { onMounted, onUnmounted, watch } from "vue";
import { useRoute } from "vue-router";
import Topbar from "./Topbar.vue";
import Sidebar from "./Sidebar.vue";
import { db } from "@/mock/runtime";
import { session } from "@/stores/session";
import { people } from "@/lib/queries";

const route = useRoute();
let videoTimer;
let rotateTimer;
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
  rotateTimer = setInterval(() => {
    if (!(session.rotation && route.name === "video")) return;
    const available = people().filter((person) => db.currentDevices(person.id).some((device) => device.video === "available"));
    if (!available.length) return;
    const index = available.findIndex((person) => person.id === session.person);
    session.person = available[(index + 1) % available.length].id;
  }, 30000);
  restartTrack();
});

watch(() => [route.name, session.trackPlaying, session.trackSpeed, session.trackPoints.length], restartTrack);

onUnmounted(() => {
  clearInterval(videoTimer);
  clearInterval(rotateTimer);
  clearInterval(trackTimer);
});
</script>

<template>
  <Topbar />
  <Sidebar />
  <main id="main" :class="['main', route.name + '-page']"><slot /></main>
  <div class="page-foot">示例数据</div>
</template>
