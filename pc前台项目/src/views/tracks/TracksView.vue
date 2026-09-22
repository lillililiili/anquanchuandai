<script setup>
import { computed, reactive, ref, watch } from "vue";
import { useRoute } from "vue-router";
import AppButton from "@/components/ui/AppButton.vue";
import AppEmpty from "@/components/ui/AppEmpty.vue";
import AppField from "@/components/ui/AppField.vue";
import AppIcon from "@/components/ui/AppIcon.vue";
import AppInput from "@/components/ui/AppInput.vue";
import AppPanel from "@/components/ui/AppPanel.vue";
import AppSelect from "@/components/ui/AppSelect.vue";
import AppTag from "@/components/ui/AppTag.vue";
import LocationTabs from "@/components/layout/LocationTabs.vue";
import PageHeading from "@/components/layout/PageHeading.vue";
import PlantMap from "@/components/domain/PlantMap.vue";
import { DATE } from "@/mock/data";
import { db } from "@/mock/runtime";
import { filtersOf, session } from "@/stores/session";
import { toast } from "@/stores/notify";
import { events, people, revision } from "@/lib/queries";
import { go } from "@/lib/actions";
import { previewCsv } from "@/lib/dialogs";

const route = useRoute();
const speeds = [
  ["1", "1×"],
  ["2", "2×"],
  ["4", "4×"],
];
const draft = reactive({
  personId: "",
  date: DATE,
  start: "09:00",
  end: "10:42",
});
const trackError = ref("");

const deviceOptions = computed(() => {
  revision();
  return people().map((person) => {
    const helmet = db.currentDevices(person.id).find((device) => device.type === "H");
    return [person.id, (helmet?.id || "未绑定") + " / " + person.name];
  });
});

const trackWindow = computed(() => {
  revision();
  const query = filtersOf("tracks");
  return {
    date: query.date || DATE,
    start: query.start || "09:00",
    end: query.end || "10:42",
  };
});

const segments = computed(() => {
  revision();
  const points = session.trackPoints;
  return {
    groups: [points.filter((point) => point.time <= "09:38"), points.filter((point) => point.time >= "09:46")].filter((group) => group.length),
    hasGap: points.some((point) => point.gap) && points.some((point) => point.time < "09:46"),
  };
});

const related = computed(() => {
  revision();
  return events().find((item) => item.personId === session.person && item.status !== "已核验") || null;
});

const currentPoint = computed(() => {
  revision();
  return session.trackPoints[session.trackIndex] || null;
});

function resolvedPerson(preferred) {
  const found = db.person(preferred);
  if (found?.station === session.station) return found;
  return people()[0] || null;
}

function loadFromContext() {
  trackError.value = "";
  const query = filtersOf("tracks");
  const person = resolvedPerson(route.params.id || query.personId || session.person);
  if (person) session.person = person.id;
  const date = query.date || DATE;
  const start = query.start || "09:00";
  const end = query.end || "10:42";
  try {
    session.trackPoints = person ? db.tracks(person.id, date, start, end) : [];
  } catch {
    session.trackPoints = [];
  }
  session.trackIndex = Math.min(session.trackIndex, Math.max(0, session.trackPoints.length - 1));
  draft.personId = person?.id || "";
  draft.date = date;
  draft.start = start;
  draft.end = end;
}

watch(() => [route.params.id, session.station], loadFromContext, { immediate: true });

function submitTracks() {
  trackError.value = "";
  if (draft.start >= draft.end) {
    trackError.value = "结束时间必须晚于开始时间";
    toast(trackError.value, true);
    return;
  }
  const date = draft.date || DATE;
  const start = draft.start || "09:00";
  const end = draft.end || "10:42";
  try {
    const points = db.tracks(draft.personId, date, start, end);
    const query = filtersOf("tracks");
    query.personId = draft.personId;
    query.date = date;
    query.start = start;
    query.end = end;
    draft.date = date;
    draft.start = start;
    draft.end = end;
    session.person = draft.personId;
    session.trackPoints = points;
    session.trackPlaying = false;
    session.trackIndex = 0;
    if (route.params.id) go("tracks/" + draft.personId);
  } catch (error) {
    trackError.value = error.message || "结束时间必须晚于开始时间";
    toast(trackError.value, true);
  }
}

function playTrack() {
  if (!session.trackPoints.length) {
    toast("所选时段无轨迹", true);
    return;
  }
  if (session.trackIndex >= session.trackPoints.length - 1) session.trackIndex = 0;
  session.trackPlaying = !session.trackPlaying;
}

function stopTrack() {
  session.trackPlaying = false;
  session.trackIndex = 0;
}

function seekTrack(event) {
  session.trackIndex = Number(event.target.value);
  session.trackPlaying = false;
}

function exportTracks() {
  if (!session.trackPoints.length) {
    toast("没有可导出的轨迹", true);
    return;
  }
  previewCsv(
    "历史轨迹-" + session.person + ".csv",
    ["人员", "历史关联设备", "日期", "时间", "示意横坐标", "示意纵坐标", "数据缺口起点"],
    session.trackPoints.map((point) => [
      db.person(session.person)?.name,
      point.deviceId,
      DATE,
      point.time,
      point.x,
      point.y,
      point.gap ? "是" : "否",
    ]),
  );
}
</script>

<template>
  <PageHeading title="历史轨迹" />
  <LocationTabs />
  <form class="filters" @submit.prevent="submitTracks">
    <AppField label="设备">
      <AppSelect v-model="draft.personId" name="personId" :options="deviceOptions" />
    </AppField>
    <AppField label="日期">
      <AppInput v-model="draft.date" name="date" type="date" />
    </AppField>
    <AppField label="时间范围">
      <AppInput v-model="draft.start" name="start" type="time" />
    </AppField>
    <span>—</span>
    <AppInput v-model="draft.end" name="end" type="time" />
    <AppButton type="submit" tone="primary">查询轨迹</AppButton>
    <AppButton icon="download-line" @click="exportTracks">导出轨迹</AppButton>
    <span class="spacer"></span>
    <small><AppIcon name="information-line" />位置来源：关联安全帽</small>
    <p v-if="trackError" class="form-error" role="alert">{{ trackError }}</p>
  </form>
  <div class="tracks-layout">
    <AppPanel title="轨迹片段与事件">
      <template v-if="session.trackPoints.length">
        <template v-for="(group, index) in segments.groups" :key="index">
          <div v-if="index && segments.hasGap" class="track-segment">
            <b class="yellow">09:38 — 09:46</b>
            <small class="yellow">数据缺口</small>
            <small>缺口时段无可靠位置，不插值连线。</small>
          </div>
          <div class="track-segment">
            <b><AppTag>{{ index + 1 }}</AppTag>　{{ group[0].time }} — {{ group[group.length - 1].time }}</b>
            <small class="blue">有效片段</small>
            <small>轨迹点　{{ group.length }} 个</small>
          </div>
        </template>
        <div class="detail-section">
          <h3>事件记录</h3>
          <template v-if="related">
            <p class="yellow">{{ related.time }}　{{ related.title }}</p>
            <p><small>关联事件　{{ related.id }}</small></p>
            <a class="btn wide" :href="'#/event/' + related.id">查看核验</a>
          </template>
          <AppEmpty v-else text="无关联事件" />
        </div>
      </template>
      <AppEmpty v-else text="所选时段无轨迹" />
    </AppPanel>
    <div class="stack">
      <div class="track-map">
        <PlantMap mode="tracks" :markers="false" />
      </div>
      <AppPanel title="轨迹回放">
        <div class="track-controls">
          <input
            class="track-progress"
            type="range"
            min="0"
            :max="Math.max(0, session.trackPoints.length - 1)"
            :value="session.trackIndex"
            aria-label="轨迹回放进度"
            @input="seekTrack"
          />
          <div class="track-labels">
            <span>{{ trackWindow.start }}</span>
            <span v-if="segments.hasGap" class="yellow">09:38 — 09:46 数据缺口</span>
            <span>{{ trackWindow.end }}</span>
          </div>
          <div class="row">
            <AppButton
              tone="primary icon-only"
              :icon="session.trackPlaying ? 'pause-fill' : 'play-fill'"
              aria-label="播放或暂停轨迹"
              @click="playTrack"
            />
            <AppButton tone="icon-only" icon="stop-fill" aria-label="停止轨迹回放" @click="stopTrack" />
            <AppSelect
              :model-value="String(session.trackSpeed)"
              name="speed"
              aria-label="回放速度"
              :options="speeds"
              @update:model-value="session.trackSpeed = Number($event)"
            />
            <span>{{ trackWindow.date }} {{ currentPoint?.time || "--:--" }}:00</span>
            <span class="spacer"></span>
            <small>当前采样点信息　{{ currentPoint ? currentPoint.deviceId : "—" }}</small>
          </div>
        </div>
      </AppPanel>
    </div>
  </div>
</template>
