<script setup>
import { computed, ref, watch } from "vue";
import AppButton from "@/components/ui/AppButton.vue";
import AppEmpty from "@/components/ui/AppEmpty.vue";
import AppField from "@/components/ui/AppField.vue";
import AppIcon from "@/components/ui/AppIcon.vue";
import AppInput from "@/components/ui/AppInput.vue";
import AppPanel from "@/components/ui/AppPanel.vue";
import AppSelect from "@/components/ui/AppSelect.vue";
import AppStatus from "@/components/ui/AppStatus.vue";
import LocationTabs from "@/components/layout/LocationTabs.vue";
import PageHeading from "@/components/layout/PageHeading.vue";
import PlantMap from "@/components/domain/PlantMap.vue";
import { db } from "@/mock/runtime";
import { filtersOf, session } from "@/stores/session";
import { openModal } from "@/stores/modal";
import { toast } from "@/stores/notify";
import { confirm } from "@/lib/dialogs";
import { revision } from "@/lib/queries";
import FenceMembersModal from "./FenceMembersModal.vue";
import FenceRecordsModal from "./FenceRecordsModal.vue";

const statusOptions = [
  ["", "全部状态"],
  ["on", "启用"],
  ["off", "停用"],
];
const statusDraft = ref(filtersOf("fences").status || "");
const fenceError = ref("");

const stationOptions = computed(() => {
  revision();
  return db.state.stations.map((item) => [item.id, item.name]);
});

const fences = computed(() => {
  revision();
  const status = filtersOf("fences").status || "";
  return db.state.fences.filter((item) => {
    if (item.station !== session.station || item.archived) return false;
    if (!status) return true;
    return status === "on" ? item.enabled : !item.enabled;
  });
});

function stationName(id) {
  return db.state.stations.find((item) => item.id === id)?.name || "";
}

function ensureFenceDraft() {
  if (session.fenceDraft) return;
  const status = filtersOf("fences").status || "";
  const list = db.state.fences.filter((item) => {
    if (item.station !== session.station || item.archived) return false;
    if (!status) return true;
    return status === "on" ? item.enabled : !item.enabled;
  });
  const selected = list.find((item) => item.id === session.fence) || list[0];
  if (!selected) return;
  session.fence = selected.id;
  session.fenceDraft = structuredClone(selected);
}

watch(
  () => {
    revision();
    return session.station + "|" + (filtersOf("fences").status || "");
  },
  () => ensureFenceDraft(),
  { immediate: true },
);

function applyStatus() {
  session.filters.fences = statusDraft.value ? { status: statusDraft.value } : {};
}

function selectFence(id) {
  const fence = db.state.fences.find((item) => item.id === id);
  if (!fence) return;
  session.fence = id;
  session.fenceDraft = structuredClone(fence);
  session.fenceMode = "select";
  session.fenceUndo = [];
  fenceError.value = "";
}

function createFence() {
  session.fence = "";
  session.fenceDraft = {
    name: "",
    points: [],
    members: [],
    enabled: true,
    enter: false,
    leave: true,
    department: "设备检修部",
    owner: "",
    station: session.station,
  };
  session.fenceUndo = [];
  session.fenceMode = "draw";
  fenceError.value = "";
  toast("请在地图上单击添加节点，双击完成");
}

function editFence() {
  if (!session.fenceDraft) {
    toast("请先新建或选择围栏", true);
    return;
  }
  session.fenceMode = "edit";
}

function cancelFence() {
  session.fenceDraft = null;
  session.fenceMode = "select";
  session.fenceUndo = [];
  fenceError.value = "";
  ensureFenceDraft();
}

function submitFence() {
  const draft = session.fenceDraft;
  if (!draft) return;
  fenceError.value = "";
  try {
    const id = db.saveFence(draft.id, {
      name: String(draft.name || "").trim(),
      points: draft.points,
      members: [...(draft.members || [])],
      enabled: !!draft.enabled,
      enter: !!draft.enter,
      leave: !!draft.leave,
      department: draft.department || "",
      owner: draft.owner || "",
      station: session.station,
    });
    session.fence = id;
    session.fenceDraft = null;
    session.fenceMode = "select";
    session.fenceUndo = [];
    ensureFenceDraft();
    toast("围栏已保存");
  } catch (error) {
    fenceError.value = error.message || "操作失败";
  }
}

function askToggle(id) {
  const saved = db.state.fences.find((item) => item.id === id);
  if (!saved) return;
  confirm(
    saved.enabled ? "停用前确认" : "启用围栏",
    saved.enabled ? "停用后不再触发该围栏进出提示，历史记录保留。" : "启用后，模拟位置变化将按围栏条件记录。",
    () => {
      try {
        db.toggleFence(id, !saved.enabled);
        session.fenceDraft = null;
        session.fenceUndo = [];
        ensureFenceDraft();
        toast("围栏状态已更新");
      } catch (error) {
        toast(error.message || "操作失败", true);
      }
    },
  );
}

function askDelete(id) {
  confirm("删除围栏", "该围栏将归档，历史进出记录保留。", () => {
    try {
      db.deleteFence(id);
      session.fenceDraft = null;
      session.fence = "";
      session.fenceUndo = [];
      ensureFenceDraft();
      toast("围栏已归档");
    } catch (error) {
      toast(error.message || "操作失败", true);
    }
  });
}

function openMembers() {
  if (!session.fenceDraft) {
    toast("请先新建或选择围栏", true);
    return;
  }
  openModal({ title: "选择围栏适用人员", view: FenceMembersModal });
}

function openRecords() {
  openModal({ title: "围栏进出记录", wide: true, view: FenceRecordsModal });
}
</script>

<template>
  <PageHeading title="电子围栏">
    <template #actions>
      <AppButton tone="primary" icon="add-line" @click="createFence">新建围栏</AppButton>
      <AppButton icon="file-list-3-line" @click="openRecords">查看进出记录</AppButton>
    </template>
  </PageHeading>
  <LocationTabs />
  <div class="fence-layout">
    <AppPanel title="围栏列表">
      <form class="filters" @submit.prevent="applyStatus">
        <AppSelect v-model="statusDraft" name="status" :options="statusOptions" />
        <AppButton type="submit" tone="small">筛选</AppButton>
      </form>
      <div
        v-for="item in fences"
        :key="item.id"
        :class="['fence-row', session.fenceDraft?.id === item.id ? 'selected' : '']"
        @click="selectFence(item.id)"
      >
        <h3>{{ item.name }}</h3>
        <div class="row space-between">
          <small>关联厂站：{{ stationName(item.station) }}</small>
          <AppStatus :color="item.enabled ? 'green' : 'muted'">{{ item.enabled ? "启用" : "停用" }}</AppStatus>
        </div>
      </div>
      <AppEmpty v-if="!fences.length" />
      <div v-if="session.fenceDraft?.id" class="form-actions" style="margin:24px 0 8px">
        <AppButton icon="edit-line" @click="editFence">编辑</AppButton>
        <AppButton icon="pause-circle-line" @click="askToggle(session.fenceDraft.id)">
          {{ session.fenceDraft.enabled ? "停用" : "启用" }}
        </AppButton>
        <AppButton tone="danger" icon="delete-bin-line" @click="askDelete(session.fenceDraft.id)">删除</AppButton>
      </div>
    </AppPanel>
    <PlantMap mode="fence" :markers="false" />
    <AppPanel :title="session.fenceDraft?.id ? '编辑围栏' : '新建围栏'">
      <form v-if="session.fenceDraft" class="form-stack" @submit.prevent="submitFence">
        <AppField label="围栏名称">
          <AppInput v-model="session.fenceDraft.name" name="name" placeholder="请输入名称" maxlength="40" required />
        </AppField>
        <AppField label="关联厂站">
          <AppSelect :model-value="session.station" name="station" :options="stationOptions" disabled />
        </AppField>
        <div class="field">
          <span>进出条件</span>
          <div class="stack">
            <label class="row"><input v-model="session.fenceDraft.enter" type="checkbox" name="enter" />进入时提示</label>
            <label class="row"><input v-model="session.fenceDraft.leave" type="checkbox" name="leave" />离开时提示</label>
          </div>
        </div>
        <AppField label="适用人员">
          <AppButton type="button" tone="wide" @click="openMembers">{{ (session.fenceDraft.members || []).length }} 人 · 选择成员</AppButton>
        </AppField>
        <AppField label="责任部门">
          <AppInput v-model="session.fenceDraft.department" name="department" />
        </AppField>
        <AppField label="责任人">
          <AppInput v-model="session.fenceDraft.owner" name="owner" />
        </AppField>
        <div class="field">
          <span>状态</span>
          <label class="row"><input v-model="session.fenceDraft.enabled" type="checkbox" name="enabled" />启用</label>
        </div>
        <div class="form-actions">
          <AppButton @click="cancelFence">取消</AppButton>
          <AppButton type="submit" tone="primary">保存围栏</AppButton>
        </div>
        <p class="form-error" role="alert">{{ fenceError }}</p>
      </form>
      <AppEmpty v-else text="请新建围栏" />
    </AppPanel>
  </div>
  <p class="note" style="text-align:center"><AppIcon name="information-line" />围栏判断依赖位置数据，位置异常时需现场核验。</p>
</template>
