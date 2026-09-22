<script setup>
import { computed, reactive, watch } from "vue";
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
import { DATE } from "@/mock/data";
import { db } from "@/mock/runtime";
import { filtersOf, session } from "@/stores/session";
import { openModal } from "@/stores/modal";
import { toast } from "@/stores/notify";
import { materials, people, revision, works } from "@/lib/queries";
import { downloadMedia, durationText } from "./media";
import MediaPreview from "./MediaPreview.vue";
import MediaPreviewFooter from "./MediaPreviewFooter.vue";

const tabs = [
  { id: "all", label: "全部资料" },
  { id: "photo", label: "照片" },
  { id: "video", label: "录像" },
];

const draft = reactive({
  deviceId: "",
  personId: "",
  workId: "",
  date: DATE,
  eventId: "",
});

function readDraft() {
  const query = filtersOf("materials");
  draft.deviceId = query.deviceId || "";
  draft.personId = query.personId || "";
  draft.workId = query.workId || "";
  draft.date = query.date || DATE;
  draft.eventId = query.eventId || "";
}

readDraft();

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
  return materials().filter(
    (item) =>
      (session.mediaTab === "all" || item.kind === session.mediaTab) &&
      (!query.personId || item.personId === query.personId) &&
      (!query.deviceId || item.deviceId === query.deviceId) &&
      (!query.workId || item.workId === query.workId) &&
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
  const media = db.state.media.find((item) => item.id === id);
  if (!media) {
    toast("资料不存在", true);
    return;
  }
  openModal({
    title: media.title,
    wide: true,
    view: MediaPreview,
    props: { mediaId: media.id },
    footer: MediaPreviewFooter,
  });
}

async function saveMedia(id) {
  try {
    await downloadMedia(id);
  } catch (error) {
    toast(error.message || "操作失败", true);
  }
}
</script>

<template>
  <PageHeading title="现场影像资料" subtitle="设备回传照片与录像的检索、查看和归档" />
  <div class="split-detail">
    <div>
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
      <div class="media-grid">
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
            <span class="video-label">示例画面 · 非实时</span>
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
          {{ selectedMedia.title }}　<AppTag>{{ selectedMedia.kind === "photo" ? "照片" : "模拟录像" }}</AppTag>
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
            {{ selectedMedia.kind === "photo" ? "查看原图" : "模拟回放" }}
          </AppButton>
          <AppButton icon="download-line" @click="saveMedia(selectedMedia.id)">下载资料</AppButton>
        </div>
        <p v-if="selectedMedia.eventId" style="margin-top:16px">
          <a class="text-link" :href="'#/event/' + selectedMedia.eventId">查看关联事件 ›</a>
        </p>
      </template>
      <AppEmpty v-else />
    </AppPanel>
  </div>
</template>
