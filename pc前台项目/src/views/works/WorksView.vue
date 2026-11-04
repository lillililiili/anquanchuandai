<script setup>
import { workOnDate, workPeriod, workPeriodText, workStatus, workSource } from '@/lib/work-business';
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
import { DATE } from "@/mock/data";
import { beijingDate } from "@/lib/location";
import { db } from "@/mock/runtime";
import { filtersOf, session } from "@/stores/session";
import { events, personName, revision, search, works } from "@/lib/queries";
import { isRealDevice, isCurrentDevice } from '@/lib/device-telemetry';

const hours = ["00:00", "04:00", "08:00", "12:00", "16:00", "20:00", "24:00"];
const statusOptions = [["", "全部"], "待开始", "进行中", "已结束", "已取消"];

const today = () => db.demoMode ? DATE : beijingDate();
const draft = reactive({ q: "", date: today(), status: "" });

watch(
  () => session.filters.works,
  (value) => {
    const query = value || {};
    draft.q = query.q || "";
    draft.date = query.date || today();
    draft.status = query.status || "";
  },
  { immediate: true },
);

const list = computed(() => {
  revision();
  const query = filtersOf("works");
  return works().filter(
    (work) =>
      search(work.name + " " + work.id, query.q) &&
      workOnDate(work, query.date || today()) &&
      (!query.status || workStatus(work) === query.status),
  );
});
const selected = computed(() => list.value.find((work) => work.id === session.work) || list.value[0] || null);
const windowDate = computed(() => session.filters.works?.date || today());

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
    date: draft.date,
    status: draft.status,
  };
}

function resetFilters() {
  session.filters.works = {};
}

function pendingCount(workId) {
  return events().filter((item) => item.workId === workId && item.status !== "已核验").length;
}

function deviceSummary(members) {
  const devices = members.flatMap(id => db.currentDevices(id)).filter(device => device.active !== false && isRealDevice(device));
  return devices.filter(item => item.online === true && isCurrentDevice(item)).length + " / " + devices.length;
}

function barStyle(work) {
  const { start, end } = workPeriod(work);
  const day = Date.parse(`${windowDate.value}T00:00:00+08:00`);
  const from = Math.max(0, Math.min(1, (Date.parse(start) - day) / 86400000));
  const to = Math.max(from, Math.min(1, (Date.parse(end) - day) / 86400000));
  return { left: `${from * 100}%`, width: `${(to - from) * 100}%` };
}

</script>

<template>
  <PageHeading title="作业监护" subtitle="对现场作业进行人员、装备和状态的实时监护" />
  <div class="works-toolbar">
    <FilterBar @submit="applyFilters" @reset="resetFilters">
      <AppField label="作业名 / 编号">
        <AppInput v-model="draft.q" name="q" placeholder="请输入作业名或编号" />
      </AppField>
      <AppField label="日期">
        <AppInput v-model="draft.date" name="date" type="date" />
      </AppField>
      <AppField label="监护状态">
        <AppSelect v-model="draft.status" name="status" :options="statusOptions" />
      </AppField>
    </FilterBar>
  </div>
  <div class="grid cols-2 bounded-split">
    <div class="stack list-detail-column">
      <AppPanel extra-class="work-list list-detail-table">
        <template #title>作业列表 <small>（共 {{ list.length }} 条）</small></template>
        <AppTable :rows="list" :reset-key="[session.station, session.filters.works]" v-slot="{ rows: pageRows }"
          :columns="['作业名称', '作业编号', '监护人', '作业地点', '人员数', '装备在线', '待核验数', '登记来源', '操作']"
          :empty="!list.length"
        >
          <tr
            v-for="work in pageRows"
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
            <td><AppStatus>{{ workSource(work) }}</AppStatus></td>
            <td><a class="btn small" :href="'#/work/' + work.id" @click.stop>查看</a></td>
          </tr>
        </AppTable>
      </AppPanel>
      <AppPanel extra-class="work-timeline-panel">
        <template #title>当日作业时间窗 <small>{{ windowDate }}</small></template>
        <div class="work-timeline">
          <div class="time-axis">
            <span></span>
            <div><span v-for="hour in hours" :key="hour">{{ hour }}</span></div>
          </div>
          <div v-for="work in list" :key="work.id" class="work-time-row">
            <span>{{ work.name }}（{{ work.members.length }}人）</span>
            <div class="work-time-track">
              <a :href="'#/work/' + work.id" :style="barStyle(work)">{{ workPeriodText(work) }}</a>
            </div>
          </div>
        </div>
      </AppPanel>
    </div>
    <AppPanel title="作业详情">
      <template v-if="selected" #extra>
        <a class="btn primary" :href="'#/work/' + selected.id">进入作业监护　<UiIcon name="chevron-right" /></a>
      </template>
      <template v-if="selected">
        <h3>{{ selected.name }}　<AppTag>{{ workStatus(selected) }}</AppTag></h3>
        <WorkInfo :work="selected" />
        <div class="detail-section">
          <h3>作业人员位置</h3>
          <div style="height:220px"><PlantMap :work="selected" :person="selected.members[0] || ''" :legend="false" :fences="false" /></div>
        </div>
        <p class="note"><AppIcon name="information-line" />{{ selected.source === 'LOCAL' ? '本地登记资料由系统管理员维护。' : '来源资料只读。' }}</p>
      </template>
      <AppEmpty v-else />
    </AppPanel>
  </div>
</template>
