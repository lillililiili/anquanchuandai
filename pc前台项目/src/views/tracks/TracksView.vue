<script setup>
import { computed, onUnmounted, reactive, ref, watch } from "vue";
import { useFieldErrors } from "@ui-spec/useFieldErrors";
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
import { db, locationApi, guardianReady } from "@/mock/runtime";
import { beijingDate, trackSegments } from "@/lib/location";
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
  mode: 'person',
  personId: "",
  deviceId: '',
  date: beijingDate(),
  start: "00:00",
  end: "23:59",
});
const trackError = ref("");
const loading = ref(false);
const unverified = ref(0);
const truncated = ref(false);
let request = 0;
let controller;
let disposed = false;
onUnmounted(() => { disposed = true; request++; controller?.abort(); session.trackPlaying = false; });
const { formRef, errors, validate } = useFieldErrors(() => ({ ...draft }));

const deviceOptions = computed(() => {
  revision();
  return db.state.devices.filter(d=>d.station===session.station && ['DIRECT_HELMET','DIRECT_BELT'].includes(d.source)).map(d=>[d.id,`${d.type==='B'?'安全带':'安全帽'} / ${d.deviceNumber || d.id}`]);
});
const personOptions=computed(()=>{revision();return db.state.people.filter(p=>p.station===session.station && p.source!=='DEMO_WATCH').map(p=>[p.id,p.name+(p.active===false?'（已停用）':'')]);});

const trackWindow = computed(() => {
  revision();
  const query = filtersOf("tracks");
  return {
    date: query.date || beijingDate(),
    start: query.start || "00:00",
    end: query.end || "23:59",
  };
});

const segments = computed(() => {
  revision();
  const points = session.trackPoints;
  const groups = trackSegments(points);
  return { groups, hasGap: groups.length > 1 };
});

const related = computed(() => {
  revision();
  const query=filtersOf('tracks');
  return events().find((item) => (query.mode==='device'?item.deviceId===query.deviceId:item.personId===session.person) && item.status !== "已核验") || null;
});

const currentPoint = computed(() => {
  revision();
  return session.trackPoints[session.trackIndex] || null;
});

function resolvedPerson(preferred) {
  const found = db.person(preferred);
  if (found?.station === session.station && found.source !== 'DEMO_WATCH') return found;
  return db.person(personOptions.value[0]?.[0]) || null;
}

async function loadFromContext() {
  trackError.value = "";
  await guardianReady;
  if (disposed) return;
  const query = filtersOf("tracks");
  const person = resolvedPerson(route.params.id || query.personId || session.person);
  if (person) session.person = person.id;
  const date = query.date || beijingDate();
  const start = query.start || "00:00";
  const end = query.end || "23:59";
  draft.personId = person?.id || "";
  draft.mode = query.mode || 'person';
  draft.deviceId = query.deviceId || deviceOptions.value[0]?.[0] || '';
  draft.date = date;
  draft.start = start;
  draft.end = end;
  await readTracks(draft.mode==='person'?person?.id:null, date, start, end, draft.mode==='device'?draft.deviceId:undefined);
}

watch(() => [route.params.id, session.station], loadFromContext, { immediate: true });

async function readTracks(personId, date, start, end, deviceId) {
  const operation = ++request;
  controller?.abort();
  controller = new AbortController();
  session.trackPlaying = false;
  session.trackPoints = [];
  session.trackIndex = 0;
  unverified.value = 0;
  truncated.value = false;
  loading.value = false;
  if (!personId && !deviceId) return;
  loading.value = true;
  try {
    const result = await locationApi.history(personId, date, start, end, { signal: controller.signal, deviceId });
    if (operation !== request) return;
    session.trackPoints = result.points;
    unverified.value = result.unverified;
    truncated.value = result.truncated;
  } catch (error) {
    if (operation === request && error.name !== "AbortError") trackError.value = error.message || "轨迹读取失败";
  } finally { if (operation === request) loading.value = false; }
}

async function submitTracks() {
  trackError.value = "";
  if (!validate({ personId: draft.mode==='person' && !draft.personId && '请选择人员', deviceId: draft.mode==='device' && !draft.deviceId && '请选择设备', end: (draft.start || '00:00') >= (draft.end || '23:59') && '结束时间必须晚于开始时间' })) return;
  const date = draft.date || beijingDate();
  const start = draft.start || "00:00";
  const end = draft.end || "23:59";
  try {
    const query = filtersOf("tracks");
    query.personId = draft.personId;
    query.mode = draft.mode;
    query.deviceId = draft.deviceId;
    query.date = date;
    query.start = start;
    query.end = end;
    draft.date = date;
    draft.start = start;
    draft.end = end;
    session.person = draft.personId;
    await readTracks(draft.mode==='person'?draft.personId:null, date, start, end, draft.mode==='device'?draft.deviceId:undefined);
    if (!disposed && route.params.id && draft.mode==='person') go("tracks/" + draft.personId);
  } catch (error) {
    trackError.value = error.message || "结束时间必须晚于开始时间";
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
    "历史轨迹-" + (filtersOf('tracks').mode === 'device' ? filtersOf('tracks').deviceId : session.person) + ".csv",
    ["人员", "历史关联设备", "日期（北京时间）", "时间", "经度", "纬度", "坐标系", "定位来源", "时间依据", "设备采集时间", "平台接收时间", "数据缺口起点"],
    session.trackPoints.map((point) => [
      db.person(point.personId)?.name || '未关联人员',
      point.deviceId,
      trackWindow.value.date,
      point.time,
      point.longitude,
      point.latitude,
      point.coordinateSystem,
      point.locationSource || "未知",
      point.locationTimeBasis === 'DEVICE_COLLECTED_AT' ? '设备采集时间' : '上报接收时间，采集时间未确认',
      point.collectedAt || '未确认',
      point.receivedAt || (point.locationTimeBasis === 'RECEIVED_AT' ? point.reportedAt : '') || '未提供',
      point.gap ? "是" : "否",
    ]),
  );
}
</script>

<template>
  <PageHeading title="历史轨迹" />
  <LocationTabs />
  <form ref="formRef" novalidate class="filters" @submit.prevent="submitTracks">
    <AppField label="查询方式"><AppSelect v-model="draft.mode" :options="[['person','按人员'],['device','按设备']]" /></AppField>
    <AppField v-if="draft.mode==='person'" label="人员（含历史领用）" vertical data-field="personId" :error="errors.personId">
      <AppSelect v-model="draft.personId" name="personId" :options="personOptions" />
    </AppField>
    <AppField v-else label="设备" vertical data-field="deviceId" :error="errors.deviceId"><AppSelect v-model="draft.deviceId" name="deviceId" :options="deviceOptions" /></AppField>
    <AppField label="日期">
      <AppInput v-model="draft.date" name="date" type="date" />
    </AppField>
    <AppField label="时间范围">
      <AppInput v-model="draft.start" name="start" type="time" />
    </AppField>
    <span>—</span>
    <AppField label="结束时间" vertical data-field="end" :error="errors.end"><AppInput v-model="draft.end" name="end" type="time" /></AppField>
    <AppButton type="submit" tone="primary" :disabled="loading">{{ loading ? '正在查询…' : '查询轨迹' }}</AppButton>
    <AppButton class="filter-export" icon="download-line" :disabled="loading || !session.trackPoints.length" @click="exportTracks">导出轨迹</AppButton>
    <span class="spacer"></span>
    <small><AppIcon name="information-line" />位置来源：关联安全帽或安全带的实际定位上报</small>
    <p v-if="trackError" class="form-error" role="alert">{{ trackError }}</p>
    <p v-if="unverified" class="yellow" role="status">{{ unverified }} 个上报点的坐标系或定位质量未确认，未绘入轨迹。</p>
    <p v-if="truncated" class="yellow" role="status">记录较多，当前显示前 20000 条，请缩短查询时段查看完整轨迹。</p>
  </form>
  <div class="tracks-layout" :aria-busy="loading">
    <AppPanel title="轨迹片段与事件">
      <template v-if="session.trackPoints.length">
        <template v-for="(group, index) in segments.groups" :key="index">
          <div v-if="index && segments.hasGap" class="track-segment">
            <b class="yellow">{{ segments.groups[index - 1].at(-1).time }} — {{ group[0].time }}</b>
            <small class="yellow">数据缺口</small>
            <small>缺口时段无可靠位置，不插值连线。</small>
          </div>
          <div class="track-segment">
            <b><AppTag>{{ index + 1 }}</AppTag>　{{ group[0].time }} — {{ group[group.length - 1].time }}</b>
            <small class="blue">有效片段</small>
            <small>轨迹点　{{ group.length }} 个 · {{ group[0].deviceId }}</small>
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
      <AppEmpty v-else :text="loading ? '正在读取设备轨迹…' : trackError ? '轨迹读取失败，请重新查询' : '所选时段无可绘制轨迹'" />
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
            <span v-if="segments.hasGap" class="yellow">{{ segments.groups.length - 1 }} 处数据间断</span>
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
            <span>{{ trackWindow.date }} {{ currentPoint?.time || "--:--:--" }}</span>
            <span class="spacer"></span>
            <small>当前采样点信息　{{ currentPoint ? currentPoint.deviceId : "—" }}</small>
            <small v-if="currentPoint">时间轴按记录上报时间；设备采集时间：{{ currentPoint.collectedAt || '未确认' }}</small>
          </div>
        </div>
      </AppPanel>
    </div>
  </div>
</template>
