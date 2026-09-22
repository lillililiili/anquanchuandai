<script setup>
import { computed, reactive, watch } from "vue";
import AppButton from "@/components/ui/AppButton.vue";
import AppEmpty from "@/components/ui/AppEmpty.vue";
import AppField from "@/components/ui/AppField.vue";
import AppIcon from "@/components/ui/AppIcon.vue";
import AppInput from "@/components/ui/AppInput.vue";
import AppPanel from "@/components/ui/AppPanel.vue";
import AppSelect from "@/components/ui/AppSelect.vue";
import AppStatus from "@/components/ui/AppStatus.vue";
import AppTable from "@/components/ui/AppTable.vue";
import AppTag from "@/components/ui/AppTag.vue";
import FilterBar from "@/components/layout/FilterBar.vue";
import PageHeading from "@/components/layout/PageHeading.vue";
import PlantMap from "@/components/domain/PlantMap.vue";
import WorkInfo from "@/components/domain/WorkInfo.vue";
import AssociateWorks from "./AssociateWorks.vue";
import { areas, DATE } from "@/mock/data";
import { db } from "@/mock/runtime";
import { openModal } from "@/stores/modal";
import { toast } from "@/stores/notify";
import { filtersOf, session } from "@/stores/session";
import { runGuarded } from "@/lib/actions";
import { events, personName, revision, search, works } from "@/lib/queries";

const hours = ["06:00", "08:00", "10:00", "12:00", "14:00", "16:00", "18:00"];
const areaOptions = [["", "全部区域"], ...areas];
const statusOptions = [["", "全部"], "监护中", "已结束"];
const syncOptions = [
  ["", "全部"],
  ["yes", "已同步"],
  ["no", "待同步"],
];
const draft = reactive({ q: "", area: "", date: DATE, status: "", sync: "" });

watch(
  () => session.filters.works,
  (value) => {
    const query = value || {};
    draft.q = query.q || "";
    draft.area = query.area || "";
    draft.date = query.date || DATE;
    draft.status = query.status || "";
    draft.sync = query.sync || "";
  },
  { immediate: true },
);

const list = computed(() => {
  revision();
  const query = filtersOf("works");
  return works().filter(
    (work) =>
      search(work.name + " " + work.id, query.q) &&
      (!query.area || work.area === query.area) &&
      (!query.date || work.date === query.date) &&
      (!query.sync || (query.sync === "yes" ? work.synced : !work.synced)) &&
      (!query.status || work.status === query.status),
  );
});
const selected = computed(() => list.value.find((work) => work.id === session.work) || list.value[0] || null);
const windowDate = computed(() => session.filters.works?.date || DATE);

watch(
  selected,
  (work) => {
    if (work && session.work !== work.id) session.work = work.id;
  },
  { immediate: true },
);

function applyFilters() {
  session.filters.works = {
    q: draft.q,
    area: draft.area,
    date: draft.date,
    status: draft.status,
    sync: draft.sync,
  };
}

function resetFilters() {
  session.filters.works = {};
}

function pendingCount(workId) {
  return events().filter((item) => item.workId === workId && item.status !== "已核验").length;
}

function deviceSummary(members) {
  const devices = members.flatMap((id) => db.currentDevices(id));
  return devices.filter((item) => item.online).length + " / " + devices.length;
}

function minutes(value) {
  const [hour, minute] = String(value || "0:0").split(":");
  return Number(hour) * 60 + Number(minute);
}

function barStyle(work) {
  const start = minutes(work.start);
  const end = minutes(work.end);
  return {
    left: ((start - 360) / 720) * 100 + "%",
    width: ((end - start) / 720) * 100 + "%",
  };
}

function openAssociate() {
  openModal({ title: "关联已有作业", view: AssociateWorks });
}

function syncSource() {
  runGuarded(() => {
    db.syncWorks(session.station);
    toast("来源信息已刷新（本地模拟）");
  });
}
</script>

<template>
  <PageHeading title="作业监护" subtitle="对现场作业进行人员、装备和状态的实时监护" />
  <div class="works-toolbar">
    <FilterBar @submit="applyFilters" @reset="resetFilters">
      <AppField label="作业名 / 工作票号">
        <AppInput v-model="draft.q" name="q" placeholder="请输入作业名或工作票号" />
      </AppField>
      <AppField label="区域">
        <AppSelect v-model="draft.area" name="area" :options="areaOptions" />
      </AppField>
      <AppField label="日期">
        <AppInput v-model="draft.date" name="date" type="date" />
      </AppField>
      <AppField label="监护状态">
        <AppSelect v-model="draft.status" name="status" :options="statusOptions" />
      </AppField>
      <AppField label="同步状态">
        <AppSelect v-model="draft.sync" name="sync" :options="syncOptions" />
      </AppField>
    </FilterBar>
    <div class="works-actions" role="group" aria-label="作业管理操作">
      <AppButton tone="primary" @click="openAssociate">关联已有作业</AppButton>
      <AppButton icon="refresh-line" @click="syncSource">刷新来源</AppButton>
    </div>
  </div>
  <div class="grid cols-2">
    <div class="stack">
      <AppPanel extra-class="work-list">
        <template #title>作业列表 <small>（共 {{ list.length }} 条）</small></template>
        <AppTable
          :columns="['作业名称', '来源编号', '监护人', '区域', '人员数', '装备在线', '待核验数', '来源状态', '操作']"
          :empty="!list.length"
        >
          <tr
            v-for="work in list"
            :key="work.id"
            data-action="select-work"
            :data-id="work.id"
            :class="{ selected: work.id === selected?.id }"
            @click="session.work = work.id"
          >
            <td>{{ work.name }}</td>
            <td>{{ work.id }}</td>
            <td>{{ personName(work.supervisor) }}</td>
            <td>{{ work.area }}</td>
            <td>{{ work.members.length }} 人</td>
            <td>{{ deviceSummary(work.members) }}</td>
            <td><b class="yellow">{{ pendingCount(work.id) }}</b></td>
            <td><AppStatus :color="work.synced ? 'green' : 'yellow'">{{ work.synced ? "已同步" : "待同步" }}</AppStatus></td>
            <td><a class="btn small" :href="'#/work/' + work.id" @click.stop>查看</a></td>
          </tr>
        </AppTable>
      </AppPanel>
      <AppPanel>
        <template #title>当日作业时间窗 <small>{{ windowDate }}</small></template>
        <div class="work-timeline">
          <div class="time-axis">
            <span></span>
            <div><span v-for="hour in hours" :key="hour">{{ hour }}</span></div>
          </div>
          <div v-for="work in list" :key="work.id" class="work-time-row">
            <span>{{ work.name }}（{{ work.members.length }}人）</span>
            <div class="work-time-track">
              <a :href="'#/work/' + work.id" :style="barStyle(work)">{{ work.start }} – {{ work.end }}</a>
            </div>
          </div>
        </div>
      </AppPanel>
    </div>
    <AppPanel title="作业详情">
      <template v-if="selected" #extra>
        <a class="btn primary" :href="'#/work/' + selected.id">进入作业监护　›</a>
      </template>
      <template v-if="selected">
        <h3>{{ selected.name }}　<AppTag color="green">进行中</AppTag></h3>
        <WorkInfo :work="selected" />
        <div class="detail-section">
          <h3>作业区域示意图</h3>
          <div style="height:220px"><PlantMap :person="selected.members[0] || ''" :legend="false" /></div>
        </div>
        <p class="note"><AppIcon name="information-line" />许可及摘要以原工作票系统为准。</p>
      </template>
      <AppEmpty v-else />
    </AppPanel>
  </div>
</template>
