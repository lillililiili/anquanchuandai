<script setup>
import { computed, onBeforeUpdate, onUnmounted, ref, shallowRef, watch } from "vue";
import AppIcon from "@/components/ui/AppIcon.vue";
import { assetForPerson } from "@/mock/data";
import { db, tick } from "@/mock/runtime";
import { personName } from "@/lib/queries";
import { isRealDevice } from '@/lib/device-telemetry';
import { subscribeMedia } from '@/lib/rtc';
import { demoVideoAvailable } from '@/lib/data-mode';

const props = defineProps({
  call: { type: Object, required: true },
});

const players = ref([]);
const playback = new Map();
const remote = shallowRef(null), remoteVideo = ref(null);
const unsubscribe = subscribeMedia(stream => { remote.value = stream; });
onUnmounted(unsubscribe);
const hasRemoteVideo = computed(() => Boolean(remote.value?.getVideoTracks().length));
watch([remote, remoteVideo], () => {
  if (remoteVideo.value) { remoteVideo.value.srcObject = remote.value; void remoteVideo.value.play().catch(() => {}); }
}, { flush: 'post' });

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
    const poster = assetForPerson(personId);
    return {
      personId,
      person,
      helmet,
      real: isRealDevice(helmet),
      poster,
      source: poster.replace("scene-", "call-").replace(".png", ".webm"),
      available: demoVideoAvailable(helmet, db.demoMode),
      status: !helmet ? "未绑定安全帽" : isRealDevice(helmet) ? props.call.rtc?.video ? '等待设备视频回传' : '当前为语音通话' : !db.demoMode ? '暂无真实设备视频' : helmet.video === "off" ? "视频未开启" : "视频回传中断",
    };
  });
});
</script>

<template>
  <div :class="['call-videos', call.members.length > 1 ? 'multiple' : '']">
    <figure v-if="hasRemoteVideo" class="call-video-tile">
      <div class="call-video-frame"><video ref="remoteVideo" autoplay muted playsinline controls aria-label="本次通话远端视频" /><span class="call-video-badge">通话远端画面</span></div>
      <figcaption>设备接通身份以服务端回执为准；多人通话画面由媒体服务提供。</figcaption>
    </figure>
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
          <img v-if="db.demoMode && !tile.real" :src="'/assets/' + tile.poster" alt="现场示意场景" />
          <div class="call-video-unavailable">
            <AppIcon name="vidicon-off-line" />
            <strong>{{ tile.status }}</strong>
          </div>
        </template>
      </div>
      <figcaption>
        <strong>{{ personName(tile.personId) }}</strong>
        <small>{{ tile.helmet?.id || "未绑定" }}</small>
        <span :class="call.serverConnected || !call.rtc && call.status === '通话中' ? 'green' : 'yellow'">{{ call.rtc ? call.serverConnected ? '设备已接通（服务端确认）' : '设备接通待确认' : call.status === "通话中" ? "已接通" : "等待接听 · 画面预览" }}</span>
      </figcaption>
    </figure>
  </div>
</template>
