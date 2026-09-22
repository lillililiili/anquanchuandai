<script setup>
import { computed, onMounted, onUnmounted, ref } from "vue";
import { useRoute } from "vue-router";
import AppButton from "@/components/ui/AppButton.vue";
import AppIcon from "@/components/ui/AppIcon.vue";
import AppSelect from "@/components/ui/AppSelect.vue";
import NoticeList from "@/components/layout/NoticeList.vue";
import UserCard from "@/components/layout/UserCard.vue";
import UserActions from "@/components/layout/UserActions.vue";
import { db, tick } from "@/mock/runtime";
import { session } from "@/stores/session";
import { closeModal, openModal } from "@/stores/modal";
import { events, people, scope } from "@/lib/queries";

const route = useRoute();
const now = ref(new Date());
let timer;

const stations = computed(() => {
  tick.value;
  return db.state.stations.map((item) => [item.id, item.name]);
});
const unresolved = computed(() => {
  tick.value;
  return db.stats(scope()).unresolved;
});
const openSos = computed(() => {
  tick.value;
  return events().filter((item) => item.type === "人员求助" && item.status !== "已核验").length;
});
const clock = computed(() => {
  const value = now.value;
  const pad = (part) => String(part).padStart(2, "0");
  return `${value.getFullYear()}-${pad(value.getMonth() + 1)}-${pad(value.getDate())} ${pad(value.getHours())}:${pad(value.getMinutes())}:${pad(value.getSeconds())}`;
});

function changeStation(value) {
  session.station = value;
  localStorage.setItem("rolling-station", value);
  session.fenceDraft = null;
  session.filters = {};
  session.selectedMembers = [];
  session.person = people()[0]?.id || "";
  closeModal();
  if (["person", "work", "single", "event", "sos"].includes(route.name)) location.hash = "#/overview";
}

function openScreen(event) {
  event.preventDefault();
  const enter = document.documentElement.requestFullscreen?.();
  if (enter?.then) enter.then(() => { location.hash = "#/screen"; }).catch(() => { location.hash = "#/screen"; });
  else location.hash = "#/screen";
}

function openNotices() {
  openModal({ title: openSos.value ? "有人正在求助" : "待处理通知", tone: openSos.value ? "is-sos" : "", view: NoticeList });
}

function openUser() {
  openModal({ title: "值守员", view: UserCard, footer: UserActions });
}

onMounted(() => {
  timer = setInterval(() => {
    now.value = new Date();
  }, 1000);
});
onUnmounted(() => clearInterval(timer));
</script>

<template>
  <header class="topbar">
    <a class="brand" href="#/overview"><img src="/assets/logo.png" alt="ROLLING" /></a>
    <span class="brand-divider"></span>
    <strong>融瓴智能穿戴安全监护平台</strong>
    <div class="top-actions">
      <a class="screen-entry" href="#/screen" @click="openScreen"><AppIcon name="dashboard-3-line" />数据大屏</a>
      <AppIcon name="building-2-line" color="blue" />
      <AppSelect :model-value="session.station" :options="stations" aria-label="选择厂站" @update:model-value="changeStation" />
      <span class="top-divider"></span>
      <AppButton
        :tone="openSos ? 'icon-only notification has-sos' : 'icon-only notification'"
        icon="notification-3-line"
        :ariaLabel="openSos ? `有 ${openSos} 起 SOS 求助，共 ${unresolved} 条待处理` : `待处理通知 ${unresolved} 条`"
        @click="openNotices"
      >
        <span class="notification-count">{{ unresolved }}</span>
      </AppButton>
      <AppButton tone="plain" icon="user-fill" @click="openUser">值守员 <AppIcon name="arrow-down-s-line" /></AppButton>
      <time :datetime="now.toISOString()" aria-label="当前时间">{{ clock }}</time>
    </div>
  </header>
</template>
