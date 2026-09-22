<script setup>
import { computed, onBeforeUpdate, ref } from "vue";
import AppIcon from "@/components/ui/AppIcon.vue";
import { assetForArea } from "@/mock/data";
import { db, tick } from "@/mock/runtime";
import { personName } from "@/lib/queries";

const props = defineProps({
  call: { type: Object, required: true },
});

const players = ref([]);
const playback = new Map();

onBeforeUpdate(() => {
  playback.clear();
  players.value.forEach((player) => {
    if (!player) return;
    playback.set(player.dataset.callVideo, { time: player.currentTime, paused: player.paused });
    player.pause();
  });
});

function restore(event) {
  const player = event.target;
  const previous = playback.get(player.dataset.callVideo);
  if (!previous) {
    player.play().catch(() => {});
    return;
  }
  player.currentTime = Number.isFinite(player.duration) && player.duration > 0 ? previous.time % player.duration : previous.time;
  if (previous.paused) player.pause();
  else player.play().catch(() => {});
}

const tiles = computed(() => {
  tick.value;
  return props.call.members.map((personId) => {
    const person = db.person(personId);
    const helmet = db.currentDevices(personId).find((item) => item.type === "H");
    const poster = assetForArea(person?.area);
    return {
      personId,
      person,
      helmet,
      poster,
      source: poster.replace("scene-", "call-").replace(".png", ".webm"),
      available: helmet?.video === "available",
      status: !helmet ? "未绑定安全帽" : helmet.video === "off" ? "视频未开启" : "视频回传中断",
    };
  });
});
</script>

<template>
  <div :class="['call-videos', call.members.length > 1 ? 'multiple' : '']">
    <figure v-for="tile in tiles" :key="call.id + ':' + tile.personId" class="call-video-tile">
      <div class="call-video-frame">
        <template v-if="tile.available">
          <video
            ref="players"
            :data-call-video="call.id + ':' + tile.personId"
            :src="'/assets/' + tile.source"
            :poster="'/assets/' + tile.poster"
            autoplay
            muted
            loop
            playsinline
            controls
            preload="auto"
            :aria-label="(tile.person?.name || '') + '的模拟现场视频'"
            @loadedmetadata="restore"
            @error="(event) => (event.target.parentElement.querySelector('.call-video-error').hidden = false)"
          ></video>
          <span class="call-video-badge">模拟视频 · 非实时</span>
          <div class="call-video-error" hidden>模拟视频暂不可用，请刷新后重试</div>
        </template>
        <template v-else>
          <img :src="'/assets/' + tile.poster" :alt="(tile.person?.area || '') + '示例场景'" />
          <div class="call-video-unavailable">
            <AppIcon name="vidicon-off-line" />
            <strong>{{ tile.status }}</strong>
          </div>
        </template>
      </div>
      <figcaption>
        <strong>{{ personName(tile.personId) }}</strong>
        <small>{{ tile.helmet?.id || "未绑定" }} · {{ tile.person?.area || "—" }}</small>
        <span :class="call.status === '通话中' ? 'green' : 'yellow'">{{ call.status === "通话中" ? "已接通" : "等待接听 · 画面预览" }}</span>
      </figcaption>
    </figure>
  </div>
</template>
