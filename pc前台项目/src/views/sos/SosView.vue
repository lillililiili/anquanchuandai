<script setup>
import { computed } from "vue";
import AppButton from "@/components/ui/AppButton.vue";
import AppIcon from "@/components/ui/AppIcon.vue";
import AppPanel from "@/components/ui/AppPanel.vue";
import AppStatus from "@/components/ui/AppStatus.vue";
import AppTag from "@/components/ui/AppTag.vue";
import MissingRecord from "@/components/layout/MissingRecord.vue";
import PageHeading from "@/components/layout/PageHeading.vue";
import PlantMap from "@/components/domain/PlantMap.vue";
import VideoFrame from "@/components/domain/VideoFrame.vue";
import ConfirmText from "@/components/ui/ConfirmText.vue";
import CallRecords from "@/views/dispatch/CallRecords.vue";
import SosEndActions from "./SosEndActions.vue";
import { db } from "@/mock/runtime";
import { session } from "@/stores/session";
import { openModal } from "@/stores/modal";
import { toast } from "@/stores/notify";
import { runGuarded } from "@/lib/actions";
import { personName, revision } from "@/lib/queries";

const alarm = computed(() => {
  revision();
  return db.state.sos;
});

const linkedEvent = computed(() => {
  revision();
  const id = alarm.value?.eventId;
  return id ? db.event(id) : null;
});

const onStation = computed(() => {
  revision();
  return !!alarm.value && alarm.value.station === session.station;
});

const videoLabel = computed(() => {
  revision();
  return alarm.value?.status === "waiting" ? "待接入" : "示例画面 · 非实时";
});

const badge = computed(() => {
  revision();
  return { waiting: "等待值守员加入", active: "正在协助", ended: "协助已结束" }[alarm.value?.status] || "";
});

function openRecords() {
  openModal({ title: "通信记录", wide: true, view: CallRecords });
}

function joinSos() {
  runGuarded(() => {
    db.sos("join");
    toast("已加入 SOS 协助");
  });
}

function endSos() {
  openModal({
    title: "结束前确认",
    view: ConfirmText,
    props: { text: "确认后结束本次 SOS 协助，并保留通信记录。核验仍在告警详情中提交。" },
    footer: SosEndActions,
  });
}
</script>

<template>
  <MissingRecord v-if="!onStation" />
  <template v-else>
    <PageHeading subtitle="与告警核验是同一起安全帽求助">
      <template #title>SOS协同　<AppTag color="red">SOS</AppTag></template>
      <template #actions>
        <a v-if="linkedEvent" class="btn" :href="'#/event/' + linkedEvent.id"><AppIcon name="arrow-left-line" /> 返回核验</a>
      </template>
    </PageHeading>
    <div class="panel sos-banner">
      <AppIcon name="alarm-warning-fill" />
      <div>
        <h2>来自安全帽 {{ linkedEvent?.deviceId || alarm.deviceId }} 的 SOS 请求</h2>
        <p>人员：{{ linkedEvent?.snapshot.personName || alarm.personName || personName(alarm.personId) }}　请求时间：{{ linkedEvent ? linkedEvent.date + " " + linkedEvent.time : alarm.timeline[0]?.time }}</p>
      </div>
      <span class="session-badge">{{ badge }}</span>
      <div class="heading-actions">
        <AppButton tone="primary" icon="user-add-fill" :disabled="alarm.status === 'ended' || alarm.members.includes('operator')" @click="joinSos">加入协助</AppButton>
        <AppButton tone="danger" icon="stop-circle-line" :disabled="alarm.status === 'ended'" @click="endSos">结束协助</AppButton>
        <AppButton icon="file-list-3-line" @click="openRecords">查看通信记录</AppButton>
      </div>
    </div>
    <div class="grid sos-layout">
      <AppPanel title="求助位置">
        <PlantMap :person="alarm.personId" :legend="false" />
        <p class="note"><AppIcon name="map-pin-fill" />位置来源：安全帽　<AppTag color="yellow">位置需现场确认</AppTag></p>
      </AppPanel>
      <AppPanel title="现场视频">
        <VideoFrame :person-id="alarm.personId" :label="videoLabel" />
      </AppPanel>
      <AppPanel title="协助分组">
        <h3>现场协助</h3>
        <div class="detail-section">
          <h3>已加入　{{ alarm.members.length }}</h3>
          <div v-for="personId in alarm.members" :key="personId" class="participant">
            <AppIcon name="user-line" /> {{ personId === "operator" ? "值守员" : personName(personId) }}
            <span class="spacer"></span>
            <AppStatus>已加入</AppStatus>
          </div>
        </div>
        <div class="detail-section">
          <h3>{{ alarm.status === "ended" ? "会话状态" : "待加入" }}</h3>
          <AppStatus v-if="alarm.status === 'ended'">协助已结束，记录保留</AppStatus>
          <AppStatus v-else-if="alarm.members.includes('operator')">所有值守人员已接入</AppStatus>
          <div v-else class="participant">
            <AppIcon name="user-line" /> 值守员
            <span class="spacer"></span>
            <AppStatus color="yellow">未加入</AppStatus>
          </div>
        </div>
      </AppPanel>
    </div>
    <div style="margin-top:15px">
      <AppPanel title="事件时间线">
        <div class="timeline horizontal">
          <div v-for="(item, index) in alarm.timeline" :key="index" class="timeline-item"><time>{{ item.time }}</time>{{ item.text }}</div>
        </div>
      </AppPanel>
    </div>
  </template>
</template>
