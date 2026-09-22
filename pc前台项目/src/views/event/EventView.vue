<script setup>
import { computed, ref, watch, watchEffect } from "vue";
import { useRoute } from "vue-router";
import AppButton from "@/components/ui/AppButton.vue";
import AppField from "@/components/ui/AppField.vue";
import AppIcon from "@/components/ui/AppIcon.vue";
import AppPanel from "@/components/ui/AppPanel.vue";
import AppSelect from "@/components/ui/AppSelect.vue";
import AppStatus from "@/components/ui/AppStatus.vue";
import AppTag from "@/components/ui/AppTag.vue";
import AppTextarea from "@/components/ui/AppTextarea.vue";
import MissingRecord from "@/components/layout/MissingRecord.vue";
import PageHeading from "@/components/layout/PageHeading.vue";
import DeviceStrip from "@/components/domain/DeviceStrip.vue";
import MediaImage from "@/components/domain/MediaImage.vue";
import VideoFrame from "@/components/domain/VideoFrame.vue";
import EventMediaActions from "./EventMediaActions.vue";
import EventMediaPreview from "./EventMediaPreview.vue";
import { db } from "@/mock/runtime";
import { session } from "@/stores/session";
import { materials, personName, revision, statusColor } from "@/lib/queries";
import { go } from "@/lib/actions";
import { blobPut } from "@/lib/files";
import { openModal } from "@/stores/modal";
import { toast } from "@/stores/notify";

const route = useRoute();
const formError = ref("");
const conclusionOptions = [["", "请选择"], "设备通信异常", "需现场处理", "暂无法确认"];
const emptyForm = { conclusion: "", situation: "", measures: "" };

const eventRecord = computed(() => {
  revision();
  const raw = route.params.id;
  const id = (Array.isArray(raw) ? raw[0] : raw) || session.event;
  const item = db.event(id);
  if (!item || item.station !== session.station) return null;
  return item;
});

const verified = computed(() => {
  revision();
  return !!eventRecord.value?.verification;
});

const relatedWork = computed(() => {
  revision();
  return eventRecord.value ? db.work(eventRecord.value.workId) : null;
});

const isSos = computed(() => eventRecord.value?.type === "人员求助");

const eventMedia = computed(() => {
  revision();
  if (!eventRecord.value) return [];
  return materials().filter((item) => item.eventId === eventRecord.value.id);
});

watchEffect(() => {
  const item = eventRecord.value;
  if (!item) return;
  const current = session.formDrafts[item.id];
  if (current && typeof current === "object") return;
  const source = item.draft || {};
  session.formDrafts[item.id] = {
    conclusion: source.conclusion || "",
    situation: source.situation || "",
    measures: source.measures || "",
  };
});

const form = computed(() => {
  revision();
  const item = eventRecord.value;
  if (!item) return emptyForm;
  return session.formDrafts[item.id] || emptyForm;
});

watch(
  () => route.params.id,
  () => {
    formError.value = "";
  },
);

function formValues() {
  const source = form.value || {};
  return {
    conclusion: source.conclusion || "",
    situation: source.situation || "",
    measures: source.measures || "",
  };
}

function submitVerify() {
  const item = eventRecord.value;
  if (!item || item.verification) return;
  try {
    db.verify(item.id, formValues(), true);
    delete session.formDrafts[item.id];
    formError.value = "";
    toast("核验记录已提交，事件与统计已同步更新");
  } catch (error) {
    formError.value = error.message || String(error);
  }
}

function saveDraft() {
  const item = eventRecord.value;
  if (!item || item.verification) return;
  try {
    const values = formValues();
    db.verify(item.id, values, false);
    session.formDrafts[item.id] = values;
    formError.value = "";
    toast("核验草稿已保存");
  } catch (error) {
    toast(error.message || "操作失败", true);
  }
}

async function uploadPhoto(event) {
  const input = event.target;
  const file = input.files && input.files[0];
  const eventId = eventRecord.value?.id;
  if (!file || !eventId) return;
  try {
    if (!["image/png", "image/jpeg"].includes(file.type)) throw Error("仅支持 JPG、PNG 图片");
    if (file.size > 10 * 1024 * 1024) throw Error("图片不能超过 10MB");
    const blobId = "upload-" + crypto.randomUUID();
    await blobPut(blobId, file);
    db.addEventPhoto(eventId, blobId, file.name);
    toast("核验照片已保存");
  } catch (error) {
    toast(error.message || "操作失败", true);
  } finally {
    input.value = "";
  }
}

function previewMedia(media) {
  if (!media) {
    toast("资料不存在", true);
    return;
  }
  openModal({
    title: media.title,
    wide: true,
    view: EventMediaPreview,
    props: { media },
    footer: EventMediaActions,
  });
}

function openMaterials() {
  const item = eventRecord.value;
  if (!item) return;
  session.filters.materials = { personId: item.personId, eventId: item.id };
  session.mediaTab = "all";
  session.media = db.state.media.find((media) => media.eventId === item.id)?.id || "";
  go("materials");
}
</script>

<template>
  <MissingRecord v-if="!eventRecord" />
  <template v-else>
    <PageHeading title="事件核验详情">
      <template #actions>
        <a v-if="isSos" class="btn danger" href="#/sos"><AppIcon name="alarm-warning-line" /> SOS协同</a>
        <a class="btn" href="#/alarms"><AppIcon name="arrow-left-line" /> 返回列表</a>
      </template>
    </PageHeading>
    <div class="grid cols-2">
      <div class="stack">
        <div class="panel event-banner">
          <AppIcon name="alarm-warning-line" color="yellow" />
          <h1>{{ eventRecord.title }}</h1>
          <AppTag :color="statusColor(eventRecord.status)">{{ eventRecord.status }}</AppTag>
          <small>{{ eventRecord.snapshot.personName }} · {{ eventRecord.deviceId }} · {{ eventRecord.date }} {{ eventRecord.time }}</small>
        </div>
        <AppPanel title="事件关联信息">
          <div class="grid equal">
            <dl class="info compact">
              <dt>关联作业</dt>
              <dd>{{ eventRecord.snapshot.workName }}</dd>
              <dt>工作票</dt>
              <dd>{{ eventRecord.workId || "—" }}（只读）</dd>
            </dl>
            <dl class="info compact">
              <dt>当前监护人</dt>
              <dd>{{ personName(relatedWork?.supervisor) }}</dd>
              <dt>当前负责人</dt>
              <dd>{{ personName(relatedWork?.leader) }}</dd>
            </dl>
          </div>
        </AppPanel>
        <div class="grid equal evidence">
          <AppPanel title="现场影像证据">
            <div v-if="eventMedia[0]" class="media-preview-wrap" data-action="preview-media" :data-id="eventMedia[0].id" style="cursor:pointer" @click="previewMedia(eventMedia[0])">
              <MediaImage :media="eventMedia[0]" />
              <span class="video-label">示例画面 · 非实时</span>
            </div>
            <VideoFrame v-else :person-id="eventRecord.personId" />
          </AppPanel>
          <AppPanel title="关联装备当前状态">
            <DeviceStrip :person-id="eventRecord.personId" />
            <div v-if="eventRecord.type === '设备通信' || eventRecord.type === '安全带挂接'" class="detail-section">
              <AppStatus color="yellow">挂接及受力信息　待协议确认</AppStatus>
              <p class="note">安全带连接中断不等于挂接违规，需现场核验确认。</p>
            </div>
          </AppPanel>
        </div>
        <div class="grid equal">
          <AppPanel title="处置时间线">
            <div class="timeline">
              <div v-for="(entry, index) in eventRecord.timeline" :key="index" class="timeline-item"><time>{{ entry.time }}</time>{{ entry.text }}</div>
              <div class="timeline-item">{{ verified ? "核验记录已提交" : "核验记录尚未提交" }}</div>
            </div>
          </AppPanel>
          <AppPanel title="相关资料">
            <div class="grid equal">
              <div v-for="item in eventMedia" :key="item.id" data-action="preview-media" :data-id="item.id" style="cursor:pointer" @click="previewMedia(item)">
                <MediaImage :media="item" />
                <small>{{ item.title }}</small>
              </div>
            </div>
            <div class="form-actions">
              <AppButton icon="folder-line" @click="openMaterials">查看原始资料</AppButton>
            </div>
          </AppPanel>
        </div>
      </div>
      <div class="stack">
        <AppPanel :title="verified ? '已提交核验结果' : '填写核验结果'">
          <form class="form-stack" data-form="verify" :data-id="eventRecord.id" @submit.prevent="submitVerify">
            <AppField>
              <template #label>核验结论 <span class="red">*</span></template>
              <AppSelect v-model="form.conclusion" name="conclusion" :options="conclusionOptions" :disabled="verified" />
            </AppField>
            <AppField>
              <template #label>现场情况 <span class="red">*</span></template>
              <div>
                <AppTextarea v-model="form.situation" name="situation" maxlength="500" placeholder="请描述现场核验情况" :readonly="verified" />
                <div class="char-count">{{ String(form.situation || "").length }}/500</div>
              </div>
            </AppField>
            <AppField label="后续措施">
              <div>
                <AppTextarea v-model="form.measures" name="measures" maxlength="500" placeholder="填写安排与责任人" :readonly="verified" />
                <div class="char-count">{{ String(form.measures || "").length }}/500</div>
              </div>
            </AppField>
            <template v-if="!verified">
              <AppField label="现场照片">
                <label class="upload-area">
                  <AppIcon name="camera-fill" />添加现场照片<small>支持 JPG、PNG，单张不超过 10MB</small>
                  <input type="file" accept="image/png,image/jpeg" :data-upload-event="eventRecord.id" aria-label="添加现场照片" @change="uploadPhoto" />
                </label>
              </AppField>
              <div class="form-actions">
                <AppButton type="button" @click="saveDraft">保存草稿</AppButton>
                <AppButton type="submit" tone="primary">提交核验记录</AppButton>
              </div>
            </template>
            <div v-else class="warning-box">
              <p><AppIcon name="checkbox-circle-line" /> {{ eventRecord.verification.submittedAt }}　值守员已提交</p>
            </div>
            <p v-if="formError" class="form-error" role="alert">{{ formError }}</p>
            <p v-else class="form-error" role="alert"></p>
          </form>
        </AppPanel>
        <AppPanel title="原安监系统">
          <dl class="info compact">
            <dt><AppIcon name="lock-fill" /> {{ eventRecord.externalId }}</dt>
            <dd class="yellow">状态：{{ eventRecord.externalStatus }}</dd>
            <dt>摘要</dt>
            <dd>{{ eventRecord.externalStatus === "待回传" ? "待回传" : "回传成功（示例）" }}</dd>
            <dt>核验记录</dt>
            <dd>{{ verified ? "已提交" : "未提交" }}</dd>
          </dl>
          <p class="note"><AppIcon name="information-line" />原系统状态只读，正式结案在原安监系统完成。</p>
        </AppPanel>
      </div>
    </div>
  </template>
</template>
