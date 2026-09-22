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

const summary = computed(() => {
  revision();
  return db.stats(scope());
});
const openEvents = computed(() => events().filter((item) => item.status !== "已核验"));
const jobList = computed(() => works());
const focus = computed(() => people().find((item) => item.id === session.person) || people()[0]);
const sidePeople = computed(() => [people()[3], people()[5]].filter(Boolean));
const cards = computed(() => {
  const stats = summary.value;
  return [
    { icon: "user-line", label: "当班人员", value: stats.people.length, unit: "人", color: "blue" },
    {
      icon: "clipboard-line",
      label: "监护作业",
      value: stats.works.length,
      unit: "项",
      color: "cyan",
      detail: `${stats.assigned} 人参与　${stats.people.length - stats.assigned} 人待分配`,
    },
    { icon: "wifi-line", label: "通信在线", value: stats.online + " / " + stats.devices.length, unit: "", color: "cyan" },
    { icon: "alarm-warning-line", label: "待核验事件", value: stats.unresolved, unit: "起", color: "yellow" },
  ];
});
const equipment = computed(() => Object.entries(summary.value.byType));

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
      <AppPanel title="当前重点事件">
        <template #extra><a class="text-link" href="#/alarms">查看全部 ›</a></template>
        <AppTable :columns="['时间', '事件', '人员 / 装备', '状态']" table-class="compact" :empty="!openEvents.length">
          <tr v-for="item in openEvents" :key="item.id" @click="go('event/' + item.id)">
            <td>{{ item.time }}</td>
            <td><AppIcon :name="eventIcon(item)[0]" :color="eventIcon(item)[1]" />　{{ item.title }}</td>
            <td>{{ personName(item.personId) }} · {{ item.deviceId }}</td>
            <td><AppTag :color="statusColor(item.status)">{{ item.status }}</AppTag></td>
          </tr>
        </AppTable>
      </AppPanel>
      <AppPanel title="装备接入概况">
        <template #extra>总计 {{ summary.devices.length }}　|　在线 {{ summary.online }}</template>
        <div v-for="[type, count] in equipment" :key="type" class="progress-row">
          <img :src="'/assets/' + { H: 'helmet', B: 'harness', W: 'watch' }[type] + '.png?v=transparent-20260921'" :alt="typeNames[type]" />
          <span>{{ typeNames[type] }}</span>
          <div class="bar"><span :style="{ width: (count.total ? (count.online / count.total) * 100 : 0) + '%' }"></span></div>
          <b>{{ count.online }} / {{ count.total }}</b>
        </div>
        <p class="note" style="text-align: right">通信在线不代表佩戴合规</p>
      </AppPanel>
    </div>
  </div>
  <div class="overview-bottom">
    <AppPanel title="当班作业">
      <AppTable :columns="['作业名称', '人数', '负责人', '来源', '同步状态', '操作']" table-class="compact" :empty="!jobList.length">
        <tr v-for="work in jobList" :key="work.id">
          <td>{{ work.name }}</td>
          <td>{{ work.members.length }} 人</td>
          <td>{{ personName(work.leader) }}</td>
          <td>{{ work.source }}　{{ work.id }}</td>
          <td><AppStatus :color="work.synced ? 'green' : 'yellow'">{{ work.synced ? "已同步" : "待同步" }}</AppStatus></td>
          <td><a class="btn small" :href="'#/work/' + work.id">查看监护</a></td>
        </tr>
      </AppTable>
    </AppPanel>
    <AppPanel title="现场视频预览">
      <template #extra><a class="text-link" href="#/video">更多 ›</a></template>
      <div v-if="focus" class="overview-videos">
        <a :href="'#/single/' + focus.id"><VideoFrame :person-id="focus.id" /></a>
        <div class="stack">
          <a v-for="person in sidePeople" :key="person.id" :href="'#/single/' + person.id"><VideoFrame :person-id="person.id" /></a>
        </div>
      </div>
      <AppEmpty v-else />
    </AppPanel>
  </div>
</template>
