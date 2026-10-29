<script setup>
import { computed } from "vue";
import AppEmpty from "@/components/ui/AppEmpty.vue";
import AppIcon from "@/components/ui/AppIcon.vue";
import AppPanel from "@/components/ui/AppPanel.vue";
import AppStatCards from "@/components/ui/AppStatCards.vue";
import AppStatus from "@/components/ui/AppStatus.vue";
import AppTable from "@/components/ui/AppTable.vue";
import AppTag from "@/components/ui/AppTag.vue";
import PlantMap from "@/components/domain/PlantMap.vue";
import VideoFrame from "@/components/domain/VideoFrame.vue";
import { typeNames } from "@/mock/data";
import { db } from "@/mock/runtime";
import { session } from "@/stores/session";
import { events, people, personName, revision, scope, statusColor, works } from "@/lib/queries";
import { go } from "@/lib/actions";
import { videoPeople } from "@/lib/person-equipment";

const summary = computed(() => {
  revision();
  return db.stats(scope());
});
const openEvents = computed(() => events().filter((item) => item.status !== "已核验"));
const jobList = computed(() => works());
const cameras = computed(() => { revision(); return videoPeople(db, people()); });
const focus = computed(() => cameras.value.find((item) => item.id === session.person) || cameras.value[0]);
const sidePeople = computed(() => cameras.value.filter(person => person.id !== focus.value?.id).slice(0, 2));
const cards = computed(() => {
  const stats = summary.value;
  return [
    { icon: "user-line", label: "在册人员", value: stats.people.length, unit: "人", color: "blue" },
    {
      icon: "clipboard-line",
      label: "台账作业",
      value: stats.works.length,
      unit: "项",
      color: "cyan",
      detail: `台账关联 ${stats.assigned} 人　未关联 ${stats.people.length - stats.assigned} 人`,
    },
    { icon: "wifi-line", label: "真实领用装备在线", value: stats.online + " / " + stats.devices.length, unit: "", color: "cyan" },
    { icon: "alarm-warning-line", label: "待核验事件", value: stats.unresolved, unit: "起", color: "yellow" },
  ];
});
const equipment = computed(() => Object.entries(summary.value.byType).filter(([key, count]) => key !== 'W' || count.total > 0));

function eventIcon(item) {
  if (item.type === "位置异常" || item.type === "电子围栏") return ["map-pin-fill", "blue"];
  if (item.type === "人员求助") return ["alarm-warning-fill", "red"];
  if (item.type === "生命体征") return ["heart-pulse-line", "yellow"];
  return ["error-warning-fill", "yellow"];
}
</script>

<template>
  <AppStatCards :items="cards" variant="flat" />
  <div class="overview-layout">
    <div class="overview-map"><PlantMap popup /></div>
    <div class="stack">
      <AppPanel title="台账待核验事件">
        <template #extra><a class="text-link" href="#/alarms">查看全部 <UiIcon name="chevron-right" /></a></template>
        <AppTable :reset-key="session.station" :rows="openEvents" v-slot="{ rows: pageRows }" :columns="['时间', '事件', '人员 / 装备', '状态']" table-class="compact" :empty="!openEvents.length">
          <tr v-for="item in pageRows" :key="item.id" @click="go('event/' + item.id)">
            <td>{{ item.time }}</td>
            <td><AppIcon :name="eventIcon(item)[0]" :color="eventIcon(item)[1]" />　{{ item.title }}</td>
            <td>{{ personName(item.personId) }} · {{ item.deviceId }}</td>
            <td><AppTag :color="statusColor(item.status)">{{ item.status }}</AppTag></td>
          </tr>
        </AppTable>
      </AppPanel>
      <AppPanel :title="db.demoMode ? '领用装备概况（演示）' : '真实领用装备概况'">
        <template #extra>总计 {{ summary.devices.length }}　|　在线 {{ summary.online }}</template>
        <div v-for="[type, count] in equipment" :key="type" class="progress-row">
          <img :src="'/assets/' + { H: 'helmet', B: 'harness', W: 'watch' }[type] + '.png?v=transparent-20260921'" :alt="typeNames[type]" />
          <span>{{ typeNames[type] }}</span>
          <div class="bar"><span :style="{ width: (count.total ? (count.online / count.total) * 100 : 0) + '%' }"></span></div>
          <b>{{ count.online }} / {{ count.total }}</b>
        </div>
        <p class="note" style="text-align: right">仅统计真实来源且已领用的设备；通信在线不代表佩戴合规</p>
        <p v-if="summary.simulatedWatches.length" class="note" style="text-align: right">模拟手表 {{ summary.simulatedWatches.length }} 块 · 非实时测量，单独展示</p>
      </AppPanel>
    </div>
  </div>
  <div class="overview-bottom">
    <AppPanel title="作业台账">
      <AppTable :reset-key="session.station" :rows="jobList" v-slot="{ rows: pageRows }" :columns="['作业名称', '人数', '负责人', '来源', '同步状态', '操作']" table-class="compact" :empty="!jobList.length">
        <tr v-for="work in pageRows" :key="work.id">
          <td>{{ work.name }}</td>
          <td>{{ work.members.length }} 人</td>
          <td>{{ personName(work.leader) }}</td>
          <td>{{ work.source }}　{{ work.id }}</td>
          <td><AppStatus color="yellow">台账记录 · {{ work.date || '日期待核对' }}</AppStatus></td>
          <td><a class="btn small" :href="'#/work/' + work.id">查看监护</a></td>
        </tr>
      </AppTable>
    </AppPanel>
    <AppPanel v-if="cameras.length" title="现场视频预览">
      <template #extra><a class="text-link" href="#/video">更多 <UiIcon name="chevron-right" /></a></template>
      <div v-if="focus" class="overview-videos" :style="sidePeople.length ? {} : { gridTemplateColumns: '1fr' }">
        <VideoFrame :person-id="focus.id" preview />
        <div v-if="sidePeople.length" class="stack">
          <VideoFrame v-for="person in sidePeople" :key="person.id" :person-id="person.id" preview />
        </div>
      </div>
      <AppEmpty v-else />
    </AppPanel>
  </div>
</template>
