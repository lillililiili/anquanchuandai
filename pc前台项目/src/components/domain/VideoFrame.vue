<script setup>
import { computed } from "vue";
import AppButton from "@/components/ui/AppButton.vue";
import AppIcon from "@/components/ui/AppIcon.vue";
import { assetForPerson, DATE } from "@/mock/data";
import { db, tick } from "@/mock/runtime";
import { session } from "@/stores/session";
import { toast } from "@/stores/notify";
import { callPerson, capturePhoto, runGuarded, toggleRecording } from "@/lib/actions";
import { isRealDevice } from '@/lib/device-telemetry';
import HelmetLivePreview from './HelmetLivePreview.vue';
import { demoVideoAvailable } from '@/lib/data-mode';
import { personFeature } from '@/lib/person-equipment';

const props = defineProps({
  personId: { type: String, default: "P1" },
  asset: { type: String, default: "" },
  label: { type: String, default: "非实时" },
  showName: Boolean,
  controls: Boolean,
  frameClass: { type: String, default: "" },
  preview: Boolean,
});

const person = computed(() => {
  tick.value;
  return db.person(props.personId);
});
const helmet = computed(() => { tick.value; return db.currentDevices(props.personId).find((item) => item.type === "H"); });
const real = computed(() => isRealDevice(helmet.value) && !props.asset);
const demo = computed(() => db.demoMode && !real.value);
const feature = key => { tick.value; return personFeature(db, props.personId, key); };
const showLive = computed(() => real.value && feature('video').supported);
const picture = computed(() => props.asset || assetForPerson(props.personId));
const unavailable = computed(() => real.value ? !showLive.value : !demo.value || !props.asset && !demoVideoAvailable(helmet.value, db.demoMode));
const reason = computed(() => {
  if (!db.demoMode && !real.value) return ['暂无现场视频', '该人员未领用支持视频的安全帽'];
  if (!helmet.value) return ["未绑定安全帽", "请先领用并绑定安全帽"];
  if (real.value) return ['现场视频不可用', feature('video').reason];
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
    <HelmetLivePreview v-if="showLive" :person-id="personId" />
    <img v-else-if="demo" :src="'/assets/' + picture" alt="现场示意画面" />
    <div v-if="unavailable" class="video-unavailable">
      <AppIcon name="vidicon-off-line" />
      <strong>{{ reason[0] }}</strong>
      <small>{{ reason[1] }}</small>
    </div>
    <span v-if="demo" class="video-label">{{ label }} · 示例画面</span>
    <div v-if="showName" class="video-name">
      <b>{{ person?.name }}</b>　{{ helmet?.id || "未绑定" }}
      <small>{{ db.currentWork(personId)?.name || "待分配" }}</small>
    </div>
    <span v-if="demo" class="video-time">{{ DATE }} 10:42:18</span>
    <div v-if="controls" class="video-controls">
      <AppButton v-if="demo" tone="icon-only" :icon="session.playing ? 'pause-fill' : 'play-fill'" aria-label="播放或暂停视频" @click="session.playing = !session.playing" />
      <AppButton v-if="demo" tone="icon-only" :icon="session.volume ? 'volume-up-line' : 'volume-mute-line'" aria-label="切换视频静音" @click="session.volume = session.volume ? 0 : 50" />
      <input v-if="demo" aria-label="音量" type="range" min="0" max="100" :value="session.volume" @input="session.volume = Number($event.target.value)" />
      <span v-if="demo" data-video-time>{{ playClock }}</span>
      <div class="spacer"></div>
      <AppButton v-if="demo || feature('photo').supported" :disabled="!demo && !feature('photo').available" tone="plain" icon="camera-line" @click="runGuarded(() => capturePhoto(personId))">{{ !demo && !feature('photo').verified ? '抓拍 · 待联调' : '抓拍' }}</AppButton>
      <AppButton v-if="demo || feature('recording').supported" :disabled="!demo && !feature('recording').available && session.recording?.person !== personId" :tone="session.recording?.person === personId ? 'red plain' : 'plain'" icon="record-circle-line" @click="runGuarded(() => toggleRecording(personId))">{{ session.recording?.person === personId ? '结束录像请求' : !demo && !feature('recording').verified ? '录像 · 待联调' : '录制现场视频' }}</AppButton>
      <a class="btn plain" :href="'#/tracks/' + personId"><AppIcon name="map-pin-line" />轨迹</a>
      <AppButton v-if="demo || feature('voice').supported" tone="plain" icon="mic-line" @click="runGuarded(() => callPerson(personId))">调度通信</AppButton>
      <AppButton tone="plain" icon="fullscreen-line" @click="fullscreen">全屏</AppButton>
    </div>
  </div>
</template>
