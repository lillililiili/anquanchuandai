<script setup>
import { computed, reactive } from "vue";
import AppButton from "@/components/ui/AppButton.vue";
import AppField from "@/components/ui/AppField.vue";
import AppIcon from "@/components/ui/AppIcon.vue";
import AppInput from "@/components/ui/AppInput.vue";
import AppPanel from "@/components/ui/AppPanel.vue";
import AppSelect from "@/components/ui/AppSelect.vue";
import AppStatCards from "@/components/ui/AppStatCards.vue";
import AppStatus from "@/components/ui/AppStatus.vue";
import AppTable from "@/components/ui/AppTable.vue";
import AppTabs from "@/components/ui/AppTabs.vue";
import AppTag from "@/components/ui/AppTag.vue";
import PageHeading from "@/components/layout/PageHeading.vue";
import { DATE, typeNames } from "@/mock/data";
import { db } from "@/mock/runtime";
import { filtersOf, session } from "@/stores/session";
import { personName, revision, scope, statusColor, works } from "@/lib/queries";
import { previewCsv } from "@/lib/dialogs";

const statTabs = ["综合", "人员", "装备", "任务", "事件"].map((label) => ({ id: label, label }));
const typeKeys = ["H", "B", "W"];
const typeLabels = { H: "安全帽", B: "安全带", W: "手表" };
const verifyStates = ["待现场核验", "待认领", "处理中", "已核验"];
const segmentColors = {
  待现场核验: "#f3b744",
  待认领: "#ee786b",
  处理中: "#318add",
  已核验: "#27baa8",
};
const peopleColumns = ["人员", "班组", "所属区域", "当前作业", "已领用装备", "操作"];
const deviceColumns = ["设备", "类型", "当前领用人", "电量", "状态"];
const workColumns = ["作业名称", "编号", "监护人", "人数", "状态", "操作"];
const eventColumns = ["人员", "设备", "关联作业", "事件", "核验状态", "回传状态", "操作"];

const stored = filtersOf("statistics");
const draft = reactive({
  date: stored.date || DATE,
  workId: stored.workId || "",
});

const workOptions = computed(() => {
  revision();
  return [["", "全部作业"], ...works().map((item) => [item.id, item.name])];
});

const stats = computed(() => {
  revision();
  const query = filtersOf("statistics");
  return db.stats(scope({ date: query.date || DATE, workId: query.workId || "" }));
});

const detailKind = computed(() => {
  revision();
  if (session.statsTab === "人员") return "人员";
  if (session.statsTab === "装备") return "装备";
  if (session.statsTab === "任务") return "任务";
  return "事件";
});

const summaryCards = computed(() => {
  revision();
  const current = stats.value;
  return [
    { icon: "user-line", label: "当班人员", value: current.people.length, unit: "人", color: "blue" },
    { icon: "shield-user-line", label: "已领用装备", value: current.devices.length, unit: "件", color: "cyan" },
    { icon: "clipboard-line", label: "监护作业", value: current.works.length, unit: "项", color: "cyan" },
    { icon: "alarm-warning-line", label: "待处理事件", value: current.unresolved, unit: "起", color: "yellow" },
  ];
});

const chartMax = computed(() => {
  revision();
  return Math.max(10, ...typeKeys.map((key) => stats.value.byType[key].total));
});

const axisMarks = computed(() => {
  revision();
  return [0, 0.2, 0.4, 0.6, 0.8, 1].map((value) => Math.round(value * chartMax.value));
});

const stateCounts = computed(() => {
  revision();
  const counts = Object.fromEntries(verifyStates.map((label) => [label, 0]));
  stats.value.events.forEach((item) => {
    if (counts[item.status] !== undefined) counts[item.status] += 1;
  });
  return counts;
});

const segments = computed(() => {
  revision();
  return verifyStates
    .filter((label) => stateCounts.value[label])
    .map((label) => ({ label, count: stateCounts.value[label], color: segmentColors[label] }));
});

function barWidth(count) {
  return (count / chartMax.value) * 95 + "%";
}

function applyFilters() {
  session.filters.statistics = {
    date: draft.date,
    workId: draft.workId,
  };
  if (!draft.date) draft.date = DATE;
}

function exportStatistics() {
  const current = stats.value;
  if (session.statsTab === "人员") {
    previewCsv(
      "人员追溯.csv",
      ["姓名", "班组", "区域", "当前作业", "装备数量"],
      current.people.map((person) => [
        person.name,
        person.team,
        person.area,
        db.currentWork(person.id)?.name || "待分配",
        db.currentDevices(person.id).length,
      ]),
    );
    return;
  }
  if (session.statsTab === "装备") {
    previewCsv(
      "装备追溯.csv",
      ["编号", "类型", "当前领用人", "电量", "通信状态"],
      current.devices.map((device) => [
        device.id,
        typeNames[device.type],
        db.owner(device.id)?.name || "未领用",
        device.battery,
        device.online ? "在线" : "连接中断",
      ]),
    );
    return;
  }
  if (session.statsTab === "任务") {
    previewCsv(
      "作业追溯.csv",
      ["名称", "编号", "监护人", "人数", "状态"],
      current.works.map((work) => [
        work.name,
        work.id,
        db.person(work.supervisor)?.name,
        work.members.length,
        work.status,
      ]),
    );
    return;
  }
  previewCsv(
    "事件追溯.csv",
    ["人员", "设备", "关联作业", "事件", "发生时间", "核验状态", "外部系统状态"],
    current.events.map((item) => [
      item.snapshot.personName,
      item.deviceId,
      item.snapshot.workName,
      item.title,
      item.date + " " + item.time,
      item.status,
      item.externalStatus,
    ]),
  );
}
</script>

<template>
  <PageHeading title="统计与追溯" subtitle="按人员、装备、作业与事件追溯监护记录">
    <template #actions>
      <form class="filters" data-form="filters" style="margin:0" @submit.prevent="applyFilters">
        <AppField label="日期">
          <AppInput v-model="draft.date" name="date" type="date" />
        </AppField>
        <AppField label="作业范围">
          <AppSelect v-model="draft.workId" name="workId" :options="workOptions" />
        </AppField>
        <AppButton type="submit" tone="primary">查询</AppButton>
        <AppButton type="button" tone="primary" icon="download-line" @click="exportStatistics">导出详细记录</AppButton>
      </form>
    </template>
  </PageHeading>
  <div class="row space-between">
    <AppTabs v-model="session.statsTab" box :tabs="statTabs" />
    <small class="stats-notice"><AppIcon name="information-line" />本页为示例数据，所有统计均按当前筛选计算。</small>
  </div>
  <AppStatCards :items="summaryCards" />
  <div class="grid equal">
    <AppPanel title="三类装备连接状态（示例）">
      <template #extra>
        <div class="legend"><span><b></b>已领用</span><span class="cyan"><b></b>在线</span><small>单位：件</small></div>
      </template>
      <div class="bars-chart">
        <div v-for="key in typeKeys" :key="key" class="chart-line">
          <span>{{ typeLabels[key] }}</span>
          <div class="chart-bars">
            <div :style="{ width: barWidth(stats.byType[key].total) }"><span>{{ stats.byType[key].total }}</span></div>
            <div :style="{ width: barWidth(stats.byType[key].online) }"><span>{{ stats.byType[key].online }}</span></div>
          </div>
        </div>
        <div class="axis">
          <span v-for="(mark, index) in axisMarks" :key="index">{{ mark }}</span>
        </div>
      </div>
    </AppPanel>
    <AppPanel title="事件核验进度（示例）">
      <template #extra>单位：起</template>
      <div style="padding:12px 18px">
        <div class="row space-between">
          <div>已核验<h1>{{ stats.verified }}</h1></div>
          <div>未完成核验<h1>{{ stats.unresolved }}</h1></div>
        </div>
        <div class="segmented-bar">
          <template v-if="segments.length">
            <span v-for="segment in segments" :key="segment.label" :style="'flex:' + segment.count + ';background:' + segment.color">{{ segment.count }}</span>
          </template>
          <span v-else style="flex:1;background:#163e59">暂无事件</span>
        </div>
        <div class="row space-between">
          <div v-for="label in verifyStates" :key="label">
            <AppStatus :color="statusColor(label)">{{ label }}</AppStatus>
            <h3 style="margin:8px 0">{{ stateCounts[label] }}</h3>
          </div>
        </div>
        <p class="note">核验记录提交后计入已核验。</p>
      </div>
    </AppPanel>
  </div>
  <div style="margin-top:14px">
    <AppPanel title="详细追溯记录">
      <AppTable v-if="detailKind === '人员'" :columns="peopleColumns" :empty="!stats.people.length">
        <tr v-for="person in stats.people" :key="person.id">
          <td>{{ personName(person.id) }}</td>
          <td>{{ person.team }}</td>
          <td>{{ person.area }}</td>
          <td>{{ db.currentWork(person.id)?.name || "待分配" }}</td>
          <td>{{ db.currentDevices(person.id).length }}</td>
          <td><a class="btn small" :href="'#/person/' + person.id">查看</a></td>
        </tr>
      </AppTable>
      <AppTable v-else-if="detailKind === '装备'" :columns="deviceColumns" :empty="!stats.devices.length">
        <tr v-for="device in stats.devices" :key="device.id">
          <td>{{ device.id }}</td>
          <td>{{ typeNames[device.type] }}</td>
          <td>{{ personName(db.owner(device.id)?.id) }}</td>
          <td>{{ device.battery }}%</td>
          <td><AppStatus :color="device.online ? 'green' : 'red'">{{ device.online ? "在线" : "连接中断" }}</AppStatus></td>
        </tr>
      </AppTable>
      <AppTable v-else-if="detailKind === '任务'" :columns="workColumns" :empty="!stats.works.length">
        <tr v-for="work in stats.works" :key="work.id">
          <td>{{ work.name }}</td>
          <td>{{ work.id }}</td>
          <td>{{ personName(work.supervisor) }}</td>
          <td>{{ work.members.length }}</td>
          <td><AppTag>{{ work.status }}</AppTag></td>
          <td><a class="btn small" :href="'#/work/' + work.id">查看</a></td>
        </tr>
      </AppTable>
      <AppTable v-else :columns="eventColumns" table-class="compact" :empty="!stats.events.length">
        <tr v-for="item in stats.events" :key="item.id">
          <td>{{ item.snapshot.personName }}</td>
          <td>{{ item.deviceId }}</td>
          <td>{{ item.snapshot.workName }}</td>
          <td>{{ item.title }} {{ item.time }}</td>
          <td><AppTag :color="statusColor(item.status)">{{ item.status }}</AppTag></td>
          <td>
            <AppStatus v-if="item.externalStatus === '待回传'" color="muted">待回传</AppStatus>
            <AppStatus v-else>摘要成功（示例）</AppStatus>
          </td>
          <td><a class="btn small" :href="'#/event/' + item.id">查看</a></td>
        </tr>
      </AppTable>
    </AppPanel>
  </div>
  <p class="note">统计口径：当前筛选 {{ stats.people.length }} 人，3 类装备共 {{ stats.devices.length }} 件；正式事件结案以原安监系统为准。</p>
</template>
