<script setup>
import { onUnmounted, ref } from "vue";
import AppButton from "@/components/ui/AppButton.vue";
import MediaImage from "@/components/domain/MediaImage.vue";

const props = defineProps({
  media: { type: Object, required: true },
});

const progress = ref(0);
const playing = ref(false);
const ended = ref(false);
let timer = 0;

function clock(value) {
  const total = Number(value) || 0;
  return Math.floor(total / 60).toString().padStart(2, "0") + ":" + (total % 60).toString().padStart(2, "0");
}

function stop(finished) {
  clearInterval(timer);
  timer = 0;
  playing.value = false;
  ended.value = !!finished;
}

function toggle() {
  if (timer) {
    stop(false);
    return;
  }
  const duration = Number(props.media.duration) || 0;
  if (progress.value >= duration) progress.value = 0;
  ended.value = false;
  playing.value = true;
  timer = setInterval(() => {
    progress.value += 1;
    if (progress.value >= duration) stop(true);
  }, 1000);
}

function seek(event) {
  progress.value = Number(event.target.value);
  if (progress.value < (Number(props.media.duration) || 0)) ended.value = false;
}

onUnmounted(() => clearInterval(timer));
</script>

<template>
  <div class="media-preview-wrap">
    <MediaImage :media="media" />
  </div>
  <template v-if="media.kind === 'video'">
    <div class="note">图片模拟回放 · 记录时长 {{ media.duration }} 秒</div>
    <div class="row">
      <AppButton tone="primary" :icon="playing ? 'pause-fill' : 'play-fill'" @click="toggle">{{ playing ? "暂停" : ended ? "重播" : "播放" }}</AppButton>
      <input type="range" :value="progress" min="0" :max="media.duration || 0" style="flex:1" aria-label="录像模拟回放进度" @input="seek" />
      <span>{{ clock(progress) }} / {{ clock(media.duration) }}</span>
    </div>
  </template>
  <p class="note">{{ media.snapshot?.personName }} · {{ media.deviceId }} · {{ media.created }}</p>
</template>
