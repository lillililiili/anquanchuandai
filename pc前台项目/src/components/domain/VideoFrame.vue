<script setup>
import { computed } from "vue";
import AppButton from "@/components/ui/AppButton.vue";
import AppIcon from "@/components/ui/AppIcon.vue";
import { assetForArea, DATE } from "@/mock/data";
import { db, tick } from "@/mock/runtime";
import { session } from "@/stores/session";
import { toast } from "@/stores/notify";
import { callPerson, capturePhoto, runGuarded, toggleRecording } from "@/lib/actions";

const props = defineProps({
  personId: { type: String, default: "P1" },
  asset: { type: String, default: "" },
  label: { type: String, default: "示例画面 · 非实时" },
  showName: Boolean,
  controls: Boolean,
  frameClass: { type: String, default: "" },
});

const person = computed(() => {
  tick.value;
  return db.person(props.personId);
});
const helmet = computed(() => db.currentDevices(props.personId).find((item) => item.type === "H"));
const picture = computed(() => props.asset || assetForArea(person.value?.area));
const unavailable = computed(() => !props.asset && (!helmet.value || helmet.value.video !== "available"));
const reason = computed(() => {
  if (!helmet.value) return ["未绑定安全帽", "请先领用并绑定安全帽"];
  if (helmet.value.video === "off") return ["视频未开启", "视频通道尚未开启"];
  return ["回传中断", "保留最后画面 · 请联系现场人员"];
});
const playClock = computed(() => {
  const value = session.videoTick;
  return `${String(Math.floor(value / 60)).padStart(2, "0")}:${String(value % 60).padStart(2, "0")} / --:--`;
});

function fullscreen(event) {
  const target = event.currentTarget.closest(".video-frame");
  runGuarded(async () => {
    try {
      if (document.fullscreenElement) await document.exitFullscreen();
      else await target.requestFullscreen();
    } catch {
      toast("当前浏览器不支持全屏，请使用窗口最大化", true);
    }
  });
}
</script>

<template>
  <div :class="['video-frame', frameClass]" :data-video-person="personId">
    <img :src="'/assets/' + picture" :alt="(person?.area || '现场') + '第一人称现场画面'" />
    <div v-if="unavailable" class="video-unavailable">
      <AppIcon name="vidicon-off-line" />
      <strong>{{ reason[0] }}</strong>
      <small>{{ reason[1] }}</small>
    </div>
    <span class="video-label">{{ label }}</span>
    <div v-if="showName" class="video-name">
      <b>{{ person?.name }}</b>　{{ helmet?.id || "未绑定" }}
      <small>{{ person?.area }} · {{ db.currentWork(personId)?.name || "待分配" }}</small>
    </div>
    <span class="video-time">{{ DATE }} 10:42:18</span>
    <div v-if="controls" class="video-controls">
      <AppButton tone="icon-only" :icon="session.playing ? 'pause-fill' : 'play-fill'" aria-label="播放或暂停视频" @click="session.playing = !session.playing" />
      <AppButton tone="icon-only" :icon="session.volume ? 'volume-up-line' : 'volume-mute-line'" aria-label="切换视频静音" @click="session.volume = session.volume ? 0 : 50" />
      <input aria-label="音量" type="range" min="0" max="100" :value="session.volume" @input="session.volume = Number($event.target.value)" />
      <span data-video-time>{{ playClock }}</span>
      <div class="spacer"></div>
      <AppButton tone="plain" icon="camera-line" @click="runGuarded(() => capturePhoto(personId))">抓拍</AppButton>
      <AppButton :tone="session.recording ? 'red plain' : 'plain'" icon="record-circle-line" @click="runGuarded(() => toggleRecording(personId))">{{ session.recording ? "停止录像" : "录像" }}</AppButton>
      <a class="btn plain" :href="'#/tracks/' + personId"><AppIcon name="map-pin-line" />轨迹</a>
      <AppButton tone="plain" icon="mic-line" @click="runGuarded(() => callPerson(personId))">对讲</AppButton>
      <AppButton tone="plain" icon="fullscreen-line" @click="fullscreen">全屏</AppButton>
    </div>
  </div>
</template>
