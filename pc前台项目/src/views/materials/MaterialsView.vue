<script setup>
import { workBusinessEnabled } from '@/lib/work-business';
import { computed, onUnmounted, reactive, ref, watch } from "vue";
import AppButton from "@/components/ui/AppButton.vue";
import AppEmpty from "@/components/ui/AppEmpty.vue";
import AppField from "@/components/ui/AppField.vue";
import AppIcon from "@/components/ui/AppIcon.vue";
import AppInput from "@/components/ui/AppInput.vue";
import AppPanel from "@/components/ui/AppPanel.vue";
import AppSelect from "@/components/ui/AppSelect.vue";
import AppTabs from "@/components/ui/AppTabs.vue";
import AppTag from "@/components/ui/AppTag.vue";
import FilterBar from "@/components/layout/FilterBar.vue";
import PageHeading from "@/components/layout/PageHeading.vue";
import MediaImage from "@/components/domain/MediaImage.vue";
import { db, guardianReady } from "@/mock/runtime";
import { authFetch } from '@/lib/auth';
import { normalizeMedia, mediaKindLabel, mediaSourceLabel, mediaTime, mediaPerson } from '@/lib/media-presentation';
import { isRealDevice } from '@/lib/device-telemetry';
import { filtersOf, session } from "@/stores/session";
import { openModal, closeModal, modalView, modalProps } from "@/stores/modal";
import { toast } from "@/stores/notify";
import { materials, people, revision, works } from "@/lib/queries";
import { downloadMedia, durationText } from "./media";
import MediaPreview from "./MediaPreview.vue";
import MediaPreviewFooter from "./MediaPreviewFooter.vue";
import DeviceRecordings from './DeviceRecordings.vue';
import { mergeDeviceMedia } from '@/lib/device-media-state';

const workEnabled = computed(() => { revision(); return workBusinessEnabled(db); });
const tabs = [
  { id: "all", label: "全部资料" },
  { id: "photo", label: "照片" },
  { id: "video", label: "录像" },
];
const recordingPersonId = ref('');
const recordingPeople = computed(() => { revision(); return people().filter(person => db.currentDevices(person.id).some(device => device.type === 'H' && device.source === 'DIRECT_HELMET' && device.active !== false && device.simulated !== true && device.demo !== true)); });
const recordingPerson = computed(() => recordingPeople.value.find(person => person.id === recordingPersonId.value) || recordingPeople.value[0]);

const draft = reactive({
  deviceId: "",
  personId: "",
  workId: "",
  date: "",
  eventId: "",
});

function readDraft() {
  const query = filtersOf("materials");
  draft.deviceId = query.deviceId || "";
  draft.personId = query.personId || "";
  draft.workId = query.workId || "";
  draft.date = query.date || "";
  draft.eventId = query.eventId || "";
}

readDraft();
const deviceMedia=ref([]),mediaError=ref(''),mediaLoading=ref(false);
let mediaRequest=0,mediaController;
const deviceVersions = new Map();
const deniedDevices=ref(new Set());
let mediaInFlight=false;
function closeMediaPreview(deviceId) {
  if(modalView.value===MediaPreview&&(!deviceId||modalProps.value.file?.deviceId===deviceId))closeModal();
}
function receiveDeviceMedia({deviceId,items,accessDenied=false}) {
  if (!db.state.devices.some(item => item.id === deviceId && item.type === 'H' && isRealDevice(item) && item.station === session.station)) {deviceMedia.value=deviceMedia.value.filter(item=>item.deviceId!==deviceId);closeMediaPreview(deviceId);return;}
  const denied=new Set(deniedDevices.value);
  if(accessDenied){denied.add(deviceId);closeMediaPreview(deviceId);}else denied.delete(deviceId);
  if(modalView.value===MediaPreview&&modalProps.value.file?.deviceId===deviceId&&!(items||[]).some(item=>item.id===modalProps.value.file.id&&item.deviceId===deviceId))closeMediaPreview(deviceId);
  deniedDevices.value=denied;
  deviceVersions.set(deviceId, (deviceVersions.get(deviceId) || 0) + 1);
  deviceMedia.value=mergeDeviceMedia(deviceMedia.value,deviceId,items,session.station);
}
async function refreshDeviceMedia(background=false){
  if(background && mediaInFlight)return;
  const operation=++mediaRequest;mediaController?.abort();mediaController=new AbortController();
  mediaInFlight=true;mediaLoading.value=!background;mediaError.value='';
  await guardianReady;
  if(operation!==mediaRequest)return;
  const station=session.station;
  const observedDevice=recordingPerson.value && db.currentDevices(recordingPerson.value.id).find(item=>item.type==='H'&&isRealDevice(item));
  const devices=db.state.devices.filter(item=>item.type==='H'&&isRealDevice(item)&&item.station===station&&(!background||item.id!==observedDevice?.id));
  const failures=[];
  let index=0;
  await Promise.all(Array.from({length:Math.min(3,devices.length)},async()=>{
    while(index<devices.length){
      const device=devices[index++];
      const version=deviceVersions.get(device.id)||0;
      try{
        const response=await authFetch(`/api/guardian/v1/helmet/media?deviceId=${encodeURIComponent(device.id)}`,{signal:mediaController.signal});
        const body=await response.json();if(!response.ok)throw Object.assign(Error(body.message||'设备资料读取失败'),{status:response.status});
        if(operation===mediaRequest && station===session.station && version===(deviceVersions.get(device.id)||0))receiveDeviceMedia({deviceId:device.id,items:body.items||[]});
      }catch(reason){if(reason.name!=='AbortError'){failures.push(reason.message);if(operation===mediaRequest&&[401,403].includes(reason.status))receiveDeviceMedia({deviceId:device.id,items:[],accessDenied:true});}}
      if(operation!==mediaRequest)return;
    }
  }));
  if(operation===mediaRequest){mediaInFlight=false;mediaLoading.value=false;if(failures.length)mediaError.value=`${failures.length} 台设备的资料读取失败：${failures[0]}`;}
}
watch(()=>{revision();const operator=db.state.operator;return JSON.stringify([session.station,operator?.id,operator?.roleIds,operator?.sites,operator?.permissionsBySite,db.state.devices.filter(item=>item.type==='H'&&isRealDevice(item)&&item.station===session.station).map(item=>item.id).sort()]);},()=>{closeMediaPreview();deviceMedia.value=[];deniedDevices.value=new Set();deviceVersions.clear();void refreshDeviceMedia();},{immediate:true,flush:'sync'});
const mediaTimer=setInterval(()=>void refreshDeviceMedia(true),15000);
onUnmounted(()=>{mediaRequest++;mediaController?.abort();clearInterval(mediaTimer);closeMediaPreview();deviceMedia.value=[];});

const applied = computed(() => {
  revision();
  return filtersOf("materials");
});

const deviceOptions = computed(() => {
  revision();
  return [["", "全部设备"], ...db.state.devices.filter((item) => item.station === session.station).map((item) => [item.id, item.id])];
});

const personOptions = computed(() => {
  revision();
  return [["", "全部人员"], ...people().map((person) => [person.id, person.name])];
});

const workOptions = computed(() => {
  revision();
  return [["", "全部作业"], ...works().map((work) => [work.id, work.name])];
});

const mediaList = computed(() => {
  revision();
  const query = applied.value;
  const queriedDevices=new Set(db.state.devices.filter(item=>item.type==='H'&&item.source==='DIRECT_HELMET'&&item.station===session.station).map(item=>item.id));
  // For direct media, this page's authorized file response supersedes the
  // snapshot copy only for devices currently queried. Historical files for
  // transferred/retired devices retain the server snapshot's historical scope.
  const snapshotMedia=materials().filter(item=>item.source!=='DIRECT_HELMET'||!queriedDevices.has(item.deviceId));
  return [...new Map([...snapshotMedia,...deviceMedia.value].map(item=>[item.id,normalizeMedia(item)])).values()].filter(
    (item) =>
      !deniedDevices.value.has(item.deviceId) &&
      (session.mediaTab === "all" || item.kind === session.mediaTab) &&
      (!query.personId || item.personId === query.personId || item.receivedPersonId === query.personId) &&
      (!query.deviceId || item.deviceId === query.deviceId) &&
      (!workEnabled.value || !query.workId || item.workId === query.workId) &&
      (!query.eventId || item.eventId === query.eventId) &&
      (!query.date || item.date === query.date),
  );
});

const selectedMedia = computed(() => {
  revision();
  return mediaList.value.find((item) => item.id === session.media) || mediaList.value[0] || null;
});

watch(
  selectedMedia,
  (item) => {
    if (item && session.media !== item.id) session.media = item.id;
  },
  { immediate: true },
);

function applyFilters() {
  const next = {
    deviceId: draft.deviceId,
    personId: draft.personId,
    workId: workEnabled.value ? draft.workId : "",
    date: draft.date,
  };
  if (draft.eventId) next.eventId = draft.eventId;
  session.filters.materials = next;
}

function resetFilters() {
  session.filters.materials = {};
  readDraft();
}

function clearEventFilter() {
  const { eventId, ...remaining } = filtersOf('materials');
  session.filters.materials = remaining;
  draft.eventId = '';
}

const emptyText = computed(() => applied.value.eventId
  ? '该事件暂无关联资料，可清除事件筛选查看其他照片和录像'
  : Object.values(applied.value).some(Boolean) ? '暂无符合筛选条件的资料' : '暂无已上传的照片或录像');

function selectMedia(id) {
  session.media = id;
}

function openPreview(id) {
  const media = mediaList.value.find((item) => item.id === id);
  if (!media) {
    toast("资料不存在", true);
    return;
  }
  openModal({
    title: media.title,
    wide: true,
    view: MediaPreview,
    props: { mediaId: media.id, file: media },
    footer: MediaPreviewFooter,
  });
}

async function saveMedia(id) {
  try {
    await downloadMedia(mediaList.value.find(item=>item.id===id) || id);
  } catch (error) {
    toast(error.message || "操作失败", true);
  }
}
watch(() => { revision(); return db.state.businessConfig?.workBusinessEnabled; }, enabled => { if (enabled === false) draft.workId = ""; }, { immediate: true });
</script>

<template>
  <PageHeading title="现场影像资料" subtitle="设备回传照片与录像的检索、查看和归档"><template #actions><AppButton :disabled="mediaLoading" @click="refreshDeviceMedia()">{{ mediaLoading?'正在刷新设备资料…':'刷新设备资料' }}</AppButton></template></PageHeading>
  <p v-if="mediaError" class="form-error" role="alert">{{ mediaError }}</p>
  <div class="split-detail bounded-split">
    <div class="list-detail-column">
      <FilterBar @submit="applyFilters" @reset="resetFilters">
        <span v-if="applied.eventId" class="tag">事件 {{ applied.eventId }} <AppButton tone="small" @click="clearEventFilter">清除事件筛选</AppButton></span>
        <input v-if="applied.eventId" type="hidden" name="eventId" :value="applied.eventId" />
        <AppField label="设备编号">
          <AppSelect v-model="draft.deviceId" name="deviceId" :options="deviceOptions" />
        </AppField>
        <AppField label="关联人员（拍摄/接收）">
          <AppSelect v-model="draft.personId" name="personId" :options="personOptions" />
        </AppField>
        <AppField v-if="workEnabled" label="关联作业">
          <AppSelect v-model="draft.workId" name="workId" :options="workOptions" />
        </AppField>
        <AppField label="日期">
          <AppInput v-model="draft.date" name="date" type="date" />
        </AppField>
      </FilterBar>
      <div class="panel media-library">
        <AppTabs v-model="session.mediaTab" :tabs="tabs" />
        <div class="media-grid" tabindex="0" role="region" aria-label="资料列表，可滚动">
          <article
            v-for="item in mediaList"
            :key="item.id"
            :class="['media-card', item.id === selectedMedia?.id ? 'selected' : '']"
            tabindex="0"
            role="button"
            @click="selectMedia(item.id)"
            @keydown.enter.prevent="selectMedia(item.id)"
            @keydown.space.prevent="selectMedia(item.id)"
          >
            <div class="preview">
              <MediaImage :media="item" />
              <span class="video-label">非实时</span>
              <template v-if="item.kind === 'video'">
                <span class="play-overlay"><AppIcon name="play-fill" /></span>
                <span class="video-time">{{ durationText(item.duration) }}</span>
              </template>
            </div>
            <h3>{{ item.title }}　<AppTag>{{ mediaKindLabel(item) }}</AppTag></h3>
            <p>
              <span><AppIcon name="user-line" /> {{ item.deviceId }} · {{ mediaPerson(item).label }}：{{ mediaPerson(item).value }}</span>
              <span><AppIcon name="time-line" /> {{ mediaTime(item).label }}：{{ mediaTime(item).value }}（北京时间）</span>
            </p>
          </article>
          <AppEmpty v-if="!mediaList.length" :text="emptyText" />
        </div>
        <p class="count-label">共 {{ mediaList.length }} 条</p>
      </div>
    </div>
    <div class="materials-sidebar">
      <div v-if="recordingPeople.length" class="materials-device-recordings">
        <AppField label="当前领用人员"><AppSelect :model-value="recordingPerson?.id || ''" :options="recordingPeople.map(person => [person.id, person.name])" @update:model-value="recordingPersonId = $event" /></AppField>
        <DeviceRecordings v-if="recordingPerson" :key="session.station + ':' + recordingPerson.id" :person-id="recordingPerson.id" @media="receiveDeviceMedia" @refresh="refreshDeviceMedia()" />
      </div>
      <AppPanel title="资料详情" extra-class="media-detail">
        <template v-if="selectedMedia">
          <MediaImage :media="selectedMedia" />
          <h3 style="margin-top:18px">
            {{ selectedMedia.title }}　<AppTag>{{ mediaKindLabel(selectedMedia) }}</AppTag>
          </h3>
          <dl class="info">
            <dt>资料编号</dt>
            <dd>{{ selectedMedia.id }}</dd>
            <dt>来源</dt>
            <dd>{{ mediaSourceLabel(selectedMedia) }}</dd>
            <dt>拍摄设备</dt>
            <dd>{{ selectedMedia.deviceId }}</dd>
            <dt>{{ mediaPerson(selectedMedia).label }}</dt>
            <dd>{{ mediaPerson(selectedMedia).value }}</dd>
            <template v-if="workEnabled"><dt>关联作业</dt><dd>{{ selectedMedia.workId || "—" }}</dd></template>
            <dt>关联事件</dt>
            <dd>{{ selectedMedia.eventId || "—" }}</dd>
            <dt>{{ mediaTime(selectedMedia).label }}</dt>
            <dd>{{ mediaTime(selectedMedia).value }}（北京时间）</dd>
            <template v-if="selectedMedia.timeBasis === 'RECEIVED_AT' && !selectedMedia.capturedAt"><dt>拍摄时间</dt><dd>未提供</dd></template>
            <template v-if="selectedMedia.kind === 'video'"><dt>时长</dt><dd>{{ durationText(selectedMedia.duration) }}</dd></template>
            <dt>核验引用</dt>
            <dd>
              <AppTag v-if="selectedMedia.eventId" color="yellow">{{ db.event(selectedMedia.eventId)?.status || "待提交" }}</AppTag>
              <template v-else>—</template>
            </dd>
          </dl>
          <div class="form-actions">
            <AppButton tone="primary" icon="image-line" @click="openPreview(selectedMedia.id)">
              {{ selectedMedia.kind === "photo" ? "查看原图" : selectedMedia.url ? "播放录像" : "查看记录（暂无文件）" }}
            </AppButton>
            <AppButton icon="download-line" @click="saveMedia(selectedMedia.id)">下载资料</AppButton>
          </div>
          <p v-if="selectedMedia.eventId" style="margin-top:16px">
            <a class="text-link" :href="'#/event/' + selectedMedia.eventId">查看关联事件 <UiIcon name="chevron-right" /></a>
          </p>
        </template>
        <AppEmpty v-else />
      </AppPanel>
    </div>
  </div>
</template>
