<script setup>
import { computed } from "vue";
import { useRoute } from "vue-router";
import AppButton from "@/components/ui/AppButton.vue";
import AppIcon from "@/components/ui/AppIcon.vue";
import AppPanel from "@/components/ui/AppPanel.vue";
import AppStatus from "@/components/ui/AppStatus.vue";
import MissingRecord from "@/components/layout/MissingRecord.vue";
import MediaImage from "@/components/domain/MediaImage.vue";
import PersonAvatar from "@/components/domain/PersonAvatar.vue";
import VideoFrame from "@/components/domain/VideoFrame.vue";
import { personFeature } from '@/lib/person-equipment';
import { db } from "@/mock/runtime";
import { session } from "@/stores/session";
import { toast } from "@/stores/notify";
import { callPerson, go, runGuarded } from "@/lib/actions";
import { events, helmetOf, materials, personName, revision } from "@/lib/queries";

const route = useRoute();
const voiceFeature = computed(() => { revision(); return personFeature(db, person.value?.id, 'voice'); });
const videoFeature = computed(() => { revision(); return personFeature(db, person.value?.id, 'video'); });
const person = computed(() => {
  revision();
  const id = route.params.id || session.person;
  const record = db.person(id);
  return record && record.station === session.station ? record : null;
});
const activeCall = computed(() => {
  revision();
  if (!person.value) return null;
  return db.state.calls.find((call) => call.status !== "已结束" && call.members.includes(person.value.id)) || null;
});
const related = computed(() => {
  revision();
  if (!person.value) return null;
  return events().find((item) => item.personId === person.value.id && item.status !== "已核验") || null;
});
const recent = computed(() => {
  revision();
  if (!person.value) return [];
  return materials()
    .filter((item) => item.personId === person.value.id)
    .slice(0, 3);
});
const joined = computed(() => activeCall.value?.status === "通话中");

function openCall() {
  if (activeCall.value) {
    go("dispatch");
    return;
  }
  runGuarded(() => callPerson(person.value.id));
}

function openMedia(id) {
  session.filters.materials = {};
  session.mediaTab = "all";
  session.media = id;
  go("materials");
}

async function fullscreen(event) {
  const target = event.currentTarget.closest(".video-frame") || document.querySelector(".video-frame");
  if (!target) return;
  try {
    if (document.fullscreenElement) await document.exitFullscreen();
    else await target.requestFullscreen();
  } catch {
    toast("当前浏览器不支持全屏，请使用窗口最大化", true);
  }
}
</script>

<template>
  <MissingRecord v-if="!person" />
  <template v-else>
    <p class="muted" style="margin:4px 0 20px"><a href="#/video">视频监看</a>　<UiIcon name="chevron-right" />　{{ person.name }} · 单路监看</p>
    <div class="grid cols-2">
      <AppPanel v-if="videoFeature.supported" extra-class="flush">
        <template #title>{{ person.name }} · 单路监看　 <small>{{ helmetOf(person.id)?.id || "未绑定" }}</small></template>
        <template #extra>
          <AppButton tone="small" icon="fullscreen-line" @click="fullscreen">全屏查看</AppButton>
        </template>
        <VideoFrame :person-id="person.id" controls />
      </AppPanel>
      <AppStatus v-else>该人员当前未领用支持视频的安全帽。<a :href="'#/person/' + person.id">查看人员装备</a></AppStatus>
      <AppPanel v-if="voiceFeature.supported || activeCall" :title="voiceFeature.verified ? '远程指导' : '远程指导 · 待联调'">
        <div class="remote-box">
          <AppIcon name="vidicon-off-line" />
          <h3>{{ activeCall ? activeCall.status : "未发起通话" }}</h3>
          <p>{{ voiceFeature.reason || '前往语音调度，确认当前领用人员后发起联络。' }}</p>
          <AppButton tone="primary wide" icon="mic-line" :disabled="!activeCall && !voiceFeature.available" @click="openCall">{{ activeCall ? "查看当前通话" : "前往语音调度" }}</AppButton>
        </div>
        <h3>参与者</h3>
        <div class="participant">
          <PersonAvatar :person="{ name: '值守' }" />
          <div>值守员（我）<small style="display:block">调度中心</small></div>
          <AppStatus :color="joined ? 'green' : 'yellow'">{{ joined ? "已接入" : "待接入" }}</AppStatus>
        </div>
        <div class="participant">
          <PersonAvatar :person="person" />
          <div>{{ person.name }}<small style="display:block">{{ person.team }}</small></div>
          <AppStatus :color="joined ? 'green' : 'yellow'">{{ joined ? "已接入" : "待接入" }}</AppStatus>
        </div>
        <div v-if="related" class="warning-box" style="margin-top:15px">
          <a :href="'#/event/' + related.id"><AppIcon name="error-warning-fill" />　{{ related.title }}　<UiIcon name="chevron-right" /></a>
          <small style="display:block;margin-top:8px">{{ related.time }} 发生，{{ related.status }}</small>
        </div>

      </AppPanel>
      <AppPanel v-if="recent.length" title="最近影像 / 记录">
        <div>
          <div
            v-for="item in recent"
            :key="item.id"
            class="recent-media"
            data-action="open-media"
            :data-id="item.id"
            @click="openMedia(item.id)"
          >
            <MediaImage :media="item" />
            <div>
              {{ item.created }}
              <p class="blue">{{ personName(person.id) }} · {{ item.deviceId }}</p>
              <small>{{ item.source }}</small>
            </div>
          </div>
          <a class="text-link" href="#/materials">查看全部 <UiIcon name="chevron-right" /></a>
        </div>
      </AppPanel>
    </div>
    <p class="note"><AppIcon name="information-line" />真实设备以直播流、上传文件和指令回执为准；暂无真实影像时显示空态。</p>
  </template>
</template>
