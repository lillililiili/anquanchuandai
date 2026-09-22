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
import { db } from "@/mock/runtime";
import { session } from "@/stores/session";
import { toast } from "@/stores/notify";
import { callPerson, go, runGuarded } from "@/lib/actions";
import { events, helmetOf, materials, personName, revision } from "@/lib/queries";

const route = useRoute();
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
    <p class="muted" style="margin:4px 0 20px"><a href="#/video">视频监看</a>　›　{{ person.name }} · 单路监看</p>
    <div class="grid cols-2">
      <AppPanel extra-class="flush">
        <template #title>{{ person.name }} · 单路监看　 <small>{{ helmetOf(person.id)?.id || "未绑定" }}　|　{{ person.area }}</small></template>
        <template #extra>
          <AppButton tone="small" icon="fullscreen-line" @click="fullscreen">全屏查看</AppButton>
        </template>
        <VideoFrame :person-id="person.id" controls />
      </AppPanel>
      <AppPanel title="远程指导">
        <div class="remote-box">
          <AppIcon name="vidicon-off-line" />
          <h3>{{ activeCall ? activeCall.status : "未发起通话" }}</h3>
          <p>可与现场人员进行音视频通话，指导作业或核实异常情况。</p>
          <AppButton tone="primary wide" icon="vidicon-fill" @click="openCall">{{ activeCall ? "查看当前通话" : "发起音视频通话" }}</AppButton>
        </div>
        <h3>参与者</h3>
        <div class="participant">
          <PersonAvatar :person="{ name: '值守' }" />
          <div>值守员（我）<small style="display:block">调度中心</small></div>
          <AppStatus :color="joined ? 'green' : 'yellow'">{{ joined ? "已接入" : "待接入" }}</AppStatus>
        </div>
        <div class="participant">
          <PersonAvatar :person="person" />
          <div>{{ person.name }}<small style="display:block">{{ person.area }}</small></div>
          <AppStatus :color="joined ? 'green' : 'yellow'">{{ joined ? "已接入" : "待接入" }}</AppStatus>
        </div>
        <div v-if="related" class="warning-box" style="margin-top:15px">
          <a :href="'#/event/' + related.id"><AppIcon name="error-warning-fill" />　{{ related.title }}　›</a>
          <small style="display:block;margin-top:8px">{{ related.time }} 发生，{{ related.status }}</small>
        </div>
        <div class="detail-section">
          <h3>最近影像 / 记录</h3>
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
          <a class="text-link" href="#/materials">查看全部 ›</a>
        </div>
      </AppPanel>
    </div>
    <p class="note"><AppIcon name="information-line" />图片模拟现场视频；连接成功后显示通话状态，录像记录保留封面与时长。</p>
  </template>
</template>
