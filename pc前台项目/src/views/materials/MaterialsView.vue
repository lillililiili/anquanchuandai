<script setup>
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
import { beijingDate } from '@/lib/location';
import { isRealDevice } from '@/lib/device-telemetry';
import { filtersOf, session } from "@/stores/session";
import { openModal } from "@/stores/modal";
import { toast } from "@/stores/notify";
import { materials, people, revision, works } from "@/lib/queries";
import { downloadMedia, durationText } from "./media";
import MediaPreview from "./MediaPreview.vue";
import MediaPreviewFooter from "./MediaPreviewFooter.vue";
import DeviceRecordings from './DeviceRecordings.vue';
import { personFeature } from '@/lib/person-equipment';

const tabs = [
  { id: "all", label: "全部资料" },
  { id: "photo", label: "照片" },
  { id: "video", label: "录像" },
];
const recordingPersonId = ref('');
const recordingPeople = computed(() => { revision(); return people().filter(person => personFeature(db, person.id, 'recording').supported); });
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
async function refreshDeviceMedia(){
  const operation=++mediaRequest;mediaController?.abort();mediaController=new AbortController();
  mediaLoading.value=true;mediaError.value='';deviceMedia.value=[];
  await guardianReady;
  if(operation!==mediaRequest)return;
  const station=session.station;
  const devices=db.state.devices.filter(item=>item.type==='H'&&isRealDevice(item)&&item.station===station);
  const results=[],failures=[];
  let index=0;
  await Promise.all(Array.from({length:Math.min(3,devices.length)},async()=>{
    while(index<devices.length){
      const device=devices[index++];
      try{
        const response=await authFetch(`/api/guardian/v1/helmet/media?deviceId=${encodeURIComponent(device.id)}`,{signal:mediaController.signal});
        const body=await response.json();if(!response.ok)throw Error(body.message||'设备资料读取失败');
        for(const item of body.items||[]){
          const created=item.createdAt||item.created;
          const stamp=Date.parse(created||'');
          results.push({...item,kind:String(item.kind).toLowerCase(),station,title:item.name||'设备上传资料',created:created||'时间未提供',date:Number.isFinite(stamp)?beijingDate(stamp):'',snapshot:item.snapshot||{personName:item.personId?`${item.personId}（历史姓名未提供）`:'未关联人员'}});
        }
      }catch(reason){if(reason.name!=='AbortError')failures.push(reason.message);}
      if(operation!==mediaRequest)return;
    }
  }));
  if(operation===mediaRequest){deviceMedia.value=results;mediaLoading.value=false;if(failures.length)mediaError.value=`${failures.length} 台设备的资料读取失败：${failures[0]}`;}
}
watch(()=>session.station,refreshDeviceMedia,{immediate:true});
onUnmounted(()=>{mediaRequest++;mediaController?.abort();deviceMedia.value=[];});

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
  return [...new Map([...materials(),...deviceMedia.value].map(item=>[item.id,item])).values()].filter(
    (item) =>
      (session.mediaTab === "all" || item.kind === session.mediaTab) &&
      (!query.personId || item.personId === query.personId) &&
      (!query.deviceId || item.deviceId === query.deviceId) &&
      (!query.workId || item.workId === query.workId) &&
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
    workId: draft.workId,
    date: draft.date,
  };
  if (draft.eventId) next.eventId = draft.eventId;
  session.filters.materials = next;
}

function resetFilters() {
  session.filters.materials = {};
  readDraft();
}

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
</script>

<template>
  <PageHeading title="现场影像资料" subtitle="设备回传照片与录像的检索、查看和归档"><template #actions><AppButton :disabled="mediaLoading" @click="refreshDeviceMedia">{{ mediaLoading?'正在刷新设备资料…':'刷新设备资料' }}</AppButton></template></PageHeading>
  <template v-if="recordingPeople.length">
    <AppField label="当前领用人员"><AppSelect :model-value="recordingPerson?.id || ''" :options="recordingPeople.map(person => [person.id, person.name])" @update:model-value="recordingPersonId = $event" /></AppField>
    <DeviceRecordings v-if="recordingPerson" :key="recordingPerson.id" :person-id="recordingPerson.id" @refresh="refreshDeviceMedia" />
  </template>
  <p v-if="mediaError" class="form-error" role="alert">{{ mediaError }}</p>
  <div class="split-detail bounded-split">
    <div class="list-detail-column">
      <FilterBar @submit="applyFilters" @reset="resetFilters">
        <span v-if="applied.eventId" class="tag">事件 {{ applied.eventId }}</span>
        <input v-if="applied.eventId" type="hidden" name="eventId" :value="applied.eventId" />
        <AppField label="设备编号">
          <AppSelect v-model="draft.deviceId" name="deviceId" :options="deviceOptions" />
        </AppField>
        <AppField label="人员">
          <AppSelect v-model="draft.personId" name="personId" :options="personOptions" />
        </AppField>
        <AppField label="关联作业">
          <AppSelect v-model="draft.workId" name="workId" :options="workOptions" />
        </AppField>
        <AppField label="日期">
          <AppInput v-model="draft.date" name="date" type="date" />
        </AppField>
      </FilterBar>
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
          <h3>{{ item.title }}　<AppTag>{{ item.kind === "photo" ? "照片" : "录像 " + item.duration + "秒" }}</AppTag></h3>
          <p>
            <span><AppIcon name="user-line" /> {{ item.deviceId }} · {{ item.snapshot?.personName }}</span>
            <span><AppIcon name="time-line" /> {{ item.created }}</span>
          </p>
        </article>
        <AppEmpty v-if="!mediaList.length" />
      </div>
      <p class="count-label">共 {{ mediaList.length }} 条</p>
    </div>
    <AppPanel title="资料详情" extra-class="media-detail">
      <template v-if="selectedMedia">
        <MediaImage :media="selectedMedia" />
        <h3 style="margin-top:18px">
          {{ selectedMedia.title }}　<AppTag>{{ selectedMedia.kind === "photo" ? "照片" : selectedMedia.url ? "设备录像" : "模拟录像" }}</AppTag>
        </h3>
        <dl class="info">
          <dt>资料编号</dt>
          <dd>{{ selectedMedia.id }}</dd>
          <dt>来源</dt>
          <dd>{{ selectedMedia.source }}</dd>
          <dt>拍摄设备</dt>
          <dd>{{ selectedMedia.deviceId }}</dd>
          <dt>关联人员</dt>
          <dd>{{ selectedMedia.snapshot?.personName }}</dd>
          <dt>关联作业</dt>
          <dd>{{ selectedMedia.workId || "—" }}</dd>
          <dt>关联事件</dt>
          <dd>{{ selectedMedia.eventId || "—" }}</dd>
          <dt>拍摄时间</dt>
          <dd>{{ selectedMedia.created }}</dd>
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
</template>
