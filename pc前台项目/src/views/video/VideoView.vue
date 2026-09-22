<script setup>
import { computed, reactive, watch } from "vue";
import AppButton from "@/components/ui/AppButton.vue";
import AppEmpty from "@/components/ui/AppEmpty.vue";
import AppField from "@/components/ui/AppField.vue";
import AppPanel from "@/components/ui/AppPanel.vue";
import AppSelect from "@/components/ui/AppSelect.vue";
import AppStatCards from "@/components/ui/AppStatCards.vue";
import AppStatus from "@/components/ui/AppStatus.vue";
import DeviceStrip from "@/components/domain/DeviceStrip.vue";
import PersonAvatar from "@/components/domain/PersonAvatar.vue";
import VideoFrame from "@/components/domain/VideoFrame.vue";
import PageHeading from "@/components/layout/PageHeading.vue";
import VideoThumb from "./VideoThumb.vue";
import { areas } from "@/mock/data";
import { db } from "@/mock/runtime";
import { toast } from "@/stores/notify";
import { filtersOf, session } from "@/stores/session";
import { helmetOf, people, personName, revision, works } from "@/lib/queries";

const layouts = ["1+7", "2\u00d74", "3\u00d73"];
const areaOptions = [["", "全部区域"], ...areas];
const draft = reactive({ area: "", workId: "" });

watch(
  () => session.filters.video,
  (value) => {
    const query = value || {};
    draft.area = query.area || "";
    draft.workId = query.workId || "";
  },
  { immediate: true },
);

const workOptions = computed(() => {
  revision();
  return [["", "全部作业"], ...works().map((work) => [work.id, work.name])];
});
const cameras = computed(() => {
  revision();
  const query = filtersOf("video");
  return people().filter(
    (person) => (!query.area || person.area === query.area) && (!query.workId || db.currentWork(person.id)?.id === query.workId),
  );
});
const focus = computed(() => cameras.value.find((person) => person.id === session.person) || cameras.value[0] || null);
const cards = computed(() => {
  const counts = { available: 0, interrupted: 0, off: 0 };
  let helmets = 0;
  cameras.value.forEach((person) => {
    const devices = db.currentDevices(person.id);
    if (devices.some((device) => device.type === "H")) helmets += 1;
    const helmet = devices.find((device) => device.type === "H");
    if (helmet?.video) counts[helmet.video] += 1;
  });
  return [
    { icon: "vidicon-line", label: "帽机设备总数", value: helmets, unit: "", color: "cyan" },
    { icon: "record-circle-fill", label: "视频可用", value: counts.available || 0, unit: "", color: "green" },
    { icon: "record-circle-fill", label: "回传中断", value: counts.interrupted || 0, unit: "", color: "red" },
    { icon: "record-circle-fill", label: "未开启", value: counts.off || 0, unit: "", color: "muted" },
  ];
});

watch(
  focus,
  (person) => {
    if (person && session.person !== person.id) session.person = person.id;
  },
  { immediate: true },
);

function applyFilters() {
  session.filters.video = { area: draft.area, workId: draft.workId };
}

function toggleSound() {
  session.volume = session.volume ? 0 : 50;
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

function workOf(personId) {
  return db.currentWork(personId);
}
</script>

<template>
  <PageHeading title="现场视频墙" subtitle="来自安全帽的第一视角，支持多路视频同步查看">
    <template #actions>
      <AppStatCards :items="cards" variant="mini" />
    </template>
  </PageHeading>
  <div class="video-toolbar">
    <div class="layout-control">布局切换：<AppButton v-for="layout in layouts" :key="layout" :tone="session.layout === layout ? 'active' : ''" @click="session.layout = layout">{{ layout }}</AppButton></div>
    <form class="filters" data-form="filters" style="margin:0" @submit.prevent="applyFilters">
      <AppField label="厂区区域">
        <AppSelect v-model="draft.area" name="area" :options="areaOptions" />
      </AppField>
      <AppField label="作业筛选">
        <AppSelect v-model="draft.workId" name="workId" :options="workOptions" />
      </AppField>
      <AppButton type="submit" tone="small">筛选</AppButton>
    </form>
    <span class="spacer"></span>轮播控制：<AppButton tone="icon-only" :icon="session.rotation ? 'pause-fill' : 'play-fill'" aria-label="rotation" @click="session.rotation = !session.rotation" /><span class="blue">30秒 / {{ session.rotation ? "已开启" : "已暂停" }}</span>
  </div>
  <template v-if="session.layout === '1+7'">
    <div class="video-wall">
      <VideoFrame v-if="focus" :person-id="focus.id" show-name />
      <AppEmpty v-else />
      <AppPanel title="当前选中设备">
        <template v-if="focus">
          <div class="detail-heading">
            <PersonAvatar :person="focus" />
            <h3>{{ focus.name }}　<small>{{ helmetOf(focus.id)?.id || "未绑定" }}</small></h3>
            <AppStatus>在岗</AppStatus>
          </div>
          <dl class="info">
            <dt>所属区域</dt>
            <dd>{{ focus.area }}</dd>
            <dt>关联作业</dt>
            <dd>{{ workOf(focus.id)?.name || "待分配" }}</dd>
            <dt>监护人</dt>
            <dd>{{ personName(workOf(focus.id)?.supervisor) }}</dd>
            <dt>工作负责人</dt>
            <dd>{{ personName(workOf(focus.id)?.leader) }}</dd>
          </dl>
          <div class="detail-section">
            <h3>穿戴设备状态</h3>
            <DeviceStrip :person-id="focus.id" />
          </div>
          <div class="form-actions" style="margin-top:28px">
            <AppButton tone="primary" icon="volume-up-line" @click="toggleSound">声音</AppButton>
            <AppButton icon="fullscreen-line" @click="fullscreen">全屏</AppButton>
            <a class="btn" :href="'#/tracks/' + focus.id">查看轨迹</a>
            <a class="btn primary" :href="'#/single/' + focus.id">单路查看</a>
          </div>
        </template>
        <AppEmpty v-else />
      </AppPanel>
    </div>
    <h3 style="margin:17px 0 0">全部视频（{{ cameras.length }}）</h3>
    <div class="video-thumbs">
      <VideoThumb v-for="person in cameras" :key="person.id" :person="person" />
    </div>
  </template>
  <div v-else :class="['video-grid-wall', session.layout === layouts[2] ? 'nine' : '']">
    <VideoThumb v-for="person in cameras" :key="person.id" :person="person" />
    <div v-if="session.layout === layouts[2] && cameras.length < 9" class="panel">
      <AppEmpty text="无更多视频通道" />
    </div>
  </div>
</template>
