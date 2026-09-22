<script setup>
import { computed } from "vue";
import { useRoute } from "vue-router";
import MissingRecord from "@/components/layout/MissingRecord.vue";
import AppButton from "@/components/ui/AppButton.vue";
import AppEmpty from "@/components/ui/AppEmpty.vue";
import AppIcon from "@/components/ui/AppIcon.vue";
import AppPanel from "@/components/ui/AppPanel.vue";
import AppStatus from "@/components/ui/AppStatus.vue";
import AppTable from "@/components/ui/AppTable.vue";
import AppTag from "@/components/ui/AppTag.vue";
import DeviceStrip from "@/components/domain/DeviceStrip.vue";
import PersonAvatar from "@/components/domain/PersonAvatar.vue";
import PlantMap from "@/components/domain/PlantMap.vue";
import VideoFrame from "@/components/domain/VideoFrame.vue";
import WorkInfo from "@/components/domain/WorkInfo.vue";
import { typeNames } from "@/mock/data";
import { db } from "@/mock/runtime";
import { session } from "@/stores/session";
import { openModal } from "@/stores/modal";
import { events, revision } from "@/lib/queries";
import { callPerson, runGuarded } from "@/lib/actions";
import VitalHistoryModal from "./VitalHistoryModal.vue";
import ModalCloseFooter from "./ModalCloseFooter.vue";
import PersonEventsModal from "./PersonEventsModal.vue";

const route = useRoute();
const historyColumns = ["序号", "操作类型", "装备类型", "设备编号", "经办人", "开始时间", "结束时间", "状态"];

const person = computed(() => {
  revision();
  const raw = route.params.id;
  const id = Array.isArray(raw) ? raw[0] : raw;
  const record = db.person(id);
  if (!record || record.station !== session.station) return null;
  return record;
});

const stationName = computed(() => {
  revision();
  return db.state.stations.find((item) => item.id === person.value?.station)?.name || "";
});

const work = computed(() => {
  revision();
  return person.value ? db.currentWork(person.value.id) : null;
});

const vital = computed(() => {
  revision();
  if (!person.value) return { watch: null, record: null, status: "" };
  return db.vitals(person.value.id);
});

const metrics = computed(() => {
  const record = vital.value.record;
  return [
    { key: "heart", label: "心率", icon: "heart-pulse-line", value: record?.heartRate ?? null, unit: "bpm" },
    { key: "oxygen", label: "血氧", icon: "drop-line", value: record?.oxygen ?? null, unit: "%" },
    { key: "temperature", label: "体温", icon: "temp-hot-line", value: record ? record.temperature.toFixed(1) : null, unit: "°C" },
    {
      key: "pressure",
      label: "血压",
      icon: "pulse-line",
      value: record ? `${record.systolic} / ${record.diastolic}` : null,
      unit: "mmHg",
    },
  ];
});

const pending = computed(() => {
  revision();
  if (!person.value) return [];
  return events().filter((item) => item.personId === person.value.id && item.status !== "已核验");
});

const related = computed(() => pending.value[0] || null);

const history = computed(() => {
  revision();
  if (!person.value) return [];
  return db.state.bindings
    .filter((item) => item.personId === person.value.id)
    .sort((left, right) => right.start.localeCompare(left.start))
    .map((item) => ({
      id: item.id,
      deviceId: item.deviceId,
      operator: item.operator,
      start: item.start,
      end: item.end,
      typeName: typeNames[db.device(item.deviceId)?.type] || "装备",
    }));
});

function talk() {
  const id = person.value?.id;
  if (!id) return;
  runGuarded(() => callPerson(id));
}

function openHistory() {
  runGuarded(() => {
    const current = person.value;
    if (!current || current.station !== session.station) throw Error("人员不在当前厂站");
    openModal({
      title: current.name + " · 生命体征观测记录",
      wide: true,
      view: VitalHistoryModal,
      props: { personId: current.id },
      footer: ModalCloseFooter,
    });
  });
}

function openEvents() {
  const current = person.value;
  if (!current) return;
  openModal({
    title: "关联事件",
    view: PersonEventsModal,
    props: { personId: current.id },
  });
}
</script>

<template>
  <MissingRecord v-if="!person" />
  <template v-else>
    <div class="grid cols-2 person-main">
      <div class="stack">
        <section class="panel person-summary">
          <a class="text-link" href="#/personnel"><AppIcon name="arrow-left-line" /> 返回人员列表</a>
          <div class="row">
            <PersonAvatar :person="person" photo />
            <div>
              <h1>{{ person.name }}</h1>
              <p>{{ person.team }}　|　{{ stationName }}</p>
              <p><AppStatus>在岗</AppStatus>　当前在：{{ work?.name || "待分配" }} {{ work ? "（" + work.id + "）" : "" }}</p>
            </div>
          </div>
        </section>
        <AppPanel title="人员装备">
          <DeviceStrip :person-id="person.id" large />
        </AppPanel>
        <AppPanel v-if="vital.watch" extra-class="person-vitals">
          <template #title>生命体征 <small>（智能手表）</small></template>
          <template #extra>
            <AppButton tone="small plain" icon="history-line" @click="openHistory">观测记录</AppButton>
          </template>
          <div class="vitals-meta">
            <span>
              {{ vital.watch.id }}　<AppStatus :color="vital.watch.online ? 'green' : 'muted'">{{ vital.watch.online ? "在线" : "离线" }}</AppStatus>
            </span>
            <AppTag :color="vital.watch.online ? 'blue' : 'muted'">{{ vital.status }}</AppTag>
          </div>
          <div class="vitals-body">
            <div class="vitals-human">
              <img src="/assets/vitals-human.webp" alt="蓝色人体示意图" />
              <span>人体示意</span>
            </div>
            <article v-for="metric in metrics" :key="metric.key" :class="['vital-card', 'vital-' + metric.key]">
              <h3><AppIcon :name="metric.icon" /> {{ metric.label }}</h3>
              <p>
                <strong>{{ metric.value == null ? "—" : metric.value }}</strong><span>{{ metric.unit }}</span>
              </p>
              <small>{{ vital.record ? "本地样例 · 非实时测量" : "暂无观测数据" }}</small>
            </article>
          </div>
          <div class="vitals-footer">
            <span>观测时间：{{ vital.record ? vital.record.observedAt : "—" }}</span>
            <span>演示数据 · 非诊断</span>
          </div>
        </AppPanel>
        <AppPanel v-else title="当前位置" extra-class="flush person-location-fill">
          <div class="person-map">
            <PlantMap :person="person.id" popup :legend="false" />
          </div>
        </AppPanel>
      </div>
      <div class="stack">
        <AppPanel title="作业信息">
          <WorkInfo :work="work" />
        </AppPanel>
        <AppPanel title="待现场核验事件">
          <div v-if="related" class="warning-box">
            <h3><AppIcon name="alarm-warning-fill" />　{{ related.title }}</h3>
            <dl class="info compact">
              <dt>涉及人员</dt>
              <dd>{{ person.name }}</dd>
              <dt>设备编号</dt>
              <dd>{{ related.deviceId }}</dd>
              <dt>发生时间</dt>
              <dd>{{ related.date }} {{ related.time }}</dd>
            </dl>
            <p>设备通信状态不直接判定作业违规，需结合现场核验。</p>
          </div>
          <AppEmpty v-else text="暂无待核验事件" />
        </AppPanel>
        <AppPanel title="现场视频（来自安全帽）">
          <template #extra>示例画面 · 非实时</template>
          <div class="side-video">
            <VideoFrame :person-id="person.id" />
            <div class="stack">
              <a class="btn primary" :href="'#/single/' + person.id"><AppIcon name="play-circle-fill" /> 查看视频</a>
              <AppButton icon="mic-line" @click="talk">发起对讲</AppButton>
              <a v-if="related" class="btn" :href="'#/event/' + related.id"><AppIcon name="file-list-line" /> 查看事件</a>
              <AppButton v-else icon="file-list-line" @click="openEvents">查看事件</AppButton>
            </div>
          </div>
        </AppPanel>
      </div>
    </div>
    <div :class="['person-lower', vital.watch ? '' : 'single']">
      <AppPanel v-if="vital.watch" title="当前位置" extra-class="flush">
        <div class="person-map">
          <PlantMap :person="person.id" popup :legend="false" />
        </div>
      </AppPanel>
      <AppPanel title="领用绑定历史">
        <AppTable table-class="compact" :columns="historyColumns" :empty="!history.length">
          <tr v-for="(item, index) in history" :key="item.id">
            <td>{{ index + 1 }}</td>
            <td>领取</td>
            <td>{{ item.typeName }}</td>
            <td>{{ item.deviceId }}</td>
            <td>{{ item.operator }}</td>
            <td>{{ item.start }}</td>
            <td>{{ item.end || "—" }}</td>
            <td><AppStatus :color="item.end ? 'muted' : 'green'">{{ item.end ? "已归还" : "使用中" }}</AppStatus></td>
          </tr>
        </AppTable>
      </AppPanel>
    </div>
  </template>
</template>
