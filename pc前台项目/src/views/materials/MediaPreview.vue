<script setup>
import { computed, onUnmounted, ref, watch } from "vue";
import AppButton from "@/components/ui/AppButton.vue";
import AppEmpty from "@/components/ui/AppEmpty.vue";
import MediaImage from "@/components/domain/MediaImage.vue";
import { db } from "@/mock/runtime";
import { revision } from "@/lib/queries";
import { durationText } from "./media";

const props = defineProps({
  mediaId: { type: String, default: "" },
});

const media = computed(() => {
  revision();
  return db.state.media.find((item) => item.id === props.mediaId) || null;
});

const progress = ref(0);
const playing = ref(false);
const finished = ref(false);
let timer = null;

function stopTimer() {
  clearInterval(timer);
  timer = null;
  playing.value = false;
}

function togglePlay() {
  const current = media.value;
  if (!current) return;
  if (timer) {
    stopTimer();
    finished.value = false;
    return;
  }
  const duration = Number(current.duration) || 0;
  if (progress.value >= duration) progress.value = 0;
  finished.value = false;
  playing.value = true;
  timer = setInterval(() => {
    const item = media.value;
    if (!item) {
      stopTimer();
      return;
    }
    const limit = Number(item.duration) || 0;
    progress.value += 1;
    if (progress.value >= limit) {
      progress.value = limit;
      stopTimer();
      finished.value = true;
    }
  }, 1000);
}

function scrub(event) {
  progress.value = Number(event.target.value);
}

watch(
  () => props.mediaId,
  () => {
    stopTimer();
    progress.value = 0;
    finished.value = false;
  },
);

onUnmounted(stopTimer);
</script>

<template>
  <AppEmpty v-if="!media" text="资料不存在" />
  <template v-else>
    <div class="media-preview-wrap">
      <MediaImage :media="media" />
    </div>
    <template v-if="media.kind === 'video'">
      <div class="note">图片模拟回放 · 记录时长 {{ media.duration }} 秒</div>
      <div class="row">
        <AppButton type="button" tone="primary" :icon="playing ? 'pause-fill' : 'play-fill'" @click="togglePlay">
          {{ playing ? "暂停" : finished ? "重播" : "播放" }}
        </AppButton>
        <input
          type="range"
          :value="progress"
          min="0"
          :max="media.duration"
          style="flex:1"
          aria-label="录像模拟回放进度"
          @input="scrub"
        />
        <span id="media-play-time">{{ durationText(progress) }} / {{ durationText(media.duration) }}</span>
      </div>
    </template>
    <p class="note">{{ media.snapshot?.personName }} · {{ media.deviceId }} · {{ media.created }}</p>
  </template>
</template>
