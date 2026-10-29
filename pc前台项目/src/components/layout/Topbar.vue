<script setup>
import { computed } from "vue";
import { useRoute } from "vue-router";
import AppButton from "@/components/ui/AppButton.vue";
import AppIcon from "@/components/ui/AppIcon.vue";
import AppSelect from "@/components/ui/AppSelect.vue";
import NoticeList from "@/components/layout/NoticeList.vue";
import UserCard from "@/components/layout/UserCard.vue";
import UserActions from "@/components/layout/UserActions.vue";
import TopNavigation from "./TopNavigation.vue";
import { db, tick } from "@/mock/runtime";
import { session } from "@/stores/session";
import { closeModal, openModal } from "@/stores/modal";
import { events, people, scope } from "@/lib/queries";
import { TEST_SITE_MODE, TEST_SITE, testSiteChoices } from '../../../../shared/test-site.mjs';

const route = useRoute();
const operatorName = computed(() => {
  tick.value;
  return db.state.operator?.name || db.state.operator?.loginName || "当前账号";
});

const stations = computed(() => {
  tick.value;
  return testSiteChoices(db.state.stations, 'station').map((item) => [item.id, item.name]);
});
const stationName = computed(() => stations.value.find(([id]) => id === session.station)?.[1] || "未选择厂站");
const operatorInitial = computed(() => Array.from(operatorName.value.trim())[0] || "用");
const unresolved = computed(() => {
  tick.value;
  return db.stats(scope()).unresolved;
});
const openSos = computed(() => {
  tick.value;
  return events().filter((item) => item.type === "人员求助" && item.status !== "已核验").length;
});

function changeStation(value) {
  if (TEST_SITE_MODE && value !== TEST_SITE.stationId) return;
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
  openModal({ title: operatorName.value, view: UserCard, footer: UserActions });
}

</script>

<template>
  <TopNavigation>
    <template #left-tools>
      <a class="portal-tool screen-entry" href="#/screen" aria-label="数据大屏" data-tooltip="数据大屏" @click="openScreen"><AppIcon name="dashboard-3-line" /></a>
      <span v-if="TEST_SITE_MODE" class="portal-test-site" :aria-label="'当前厂区：' + stationName">{{ TEST_SITE.name }}</span>
      <span v-else class="portal-station-tool" :data-tooltip="'切换厂站：' + stationName">
        <AppSelect :model-value="session.station" :options="stations" :aria-label="'选择厂站，当前：' + stationName" @update:model-value="changeStation">
          <template #trigger><AppIcon name="building-2-line" /><AppIcon class="portal-tool-caret" name="arrow-down-s-line" /></template>
        </AppSelect>
      </span>
    </template>
    <template #right-tools>
      <AppButton
        :tone="openSos ? 'portal-tool icon-only notification has-sos' : 'portal-tool icon-only notification'"
        icon="notification-3-line"
        data-tooltip="待处理通知"
        :ariaLabel="openSos ? `有 ${openSos} 起 SOS 求助，共 ${unresolved} 条待处理` : `待处理通知 ${unresolved} 条`"
        @click="openNotices"
      >
        <span class="notification-count">{{ unresolved }}</span>
      </AppButton>
      <AppButton tone="portal-tool portal-account" :aria-label="'账号：' + operatorName" :data-tooltip="operatorName + ' · 账号信息'" @click="openUser">{{ operatorInitial }}</AppButton>
    </template>
  </TopNavigation>
</template>

<style scoped>
.portal-test-site { flex: 0 0 36px; width: 36px; text-align: center; font-size: 13px; line-height: 16px; }
</style>
