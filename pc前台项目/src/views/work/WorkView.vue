<script setup>
import { computed } from "vue";
import { useRoute } from "vue-router";
import AppButton from "@/components/ui/AppButton.vue";
import AppEmpty from "@/components/ui/AppEmpty.vue";
import AppIcon from "@/components/ui/AppIcon.vue";
import AppPanel from "@/components/ui/AppPanel.vue";
import AppStatCards from "@/components/ui/AppStatCards.vue";
import AppStatus from "@/components/ui/AppStatus.vue";
import AppTable from "@/components/ui/AppTable.vue";
import AppTag from "@/components/ui/AppTag.vue";
import MissingRecord from "@/components/layout/MissingRecord.vue";
import PageHeading from "@/components/layout/PageHeading.vue";
import DeviceStrip from "@/components/domain/DeviceStrip.vue";
import PersonAvatar from "@/components/domain/PersonAvatar.vue";
import PlantMap from "@/components/domain/PlantMap.vue";
import VideoFrame from "@/components/domain/VideoFrame.vue";
import ModalClose from "./ModalClose.vue";
import WorkRecords from "./WorkRecords.vue";
import WorkRiskInfo from "./WorkRiskInfo.vue";
import { db } from "@/mock/runtime";
import { openModal } from "@/stores/modal";
import { session } from "@/stores/session";
import { callPerson, runGuarded } from "@/lib/actions";
import { events, personName, revision } from "@/lib/queries";

const route = useRoute();
const record = computed(() => {
  revision();
  const work = db.work(route.params.id || session.work);
  if (!work || work.station !== session.station) return null;
  return { ...work, members: [...work.members] };
});
const camera = computed(() => {
  const work = record.value;
  if (!work) return null;
  if (work.members.includes(session.person)) {
    const person = db.person(session.person);
    if (person && person.station === session.station) return person;
  }
  return db.person(work.members[0]) || null;
});
const devices = computed(() => (record.value ? record.value.members.flatMap((id) => db.currentDevices(id)) : []));
const stats = computed(() => [
  { icon: "", label: "作业人数", value: record.value?.members.length || 0, unit: "人", color: "cyan" },
  { icon: "", label: "装备数量", value: devices.value.length, unit: "件", color: "cyan" },
  { icon: "", label: "在线装备", value: devices.value.filter((item) => item.online).length, unit: "件", color: "cyan" },
]);
const currentEvent = computed(() => {
  revision();
  const event = events().find((item) => item.workId === record.value?.id && item.status !== "已核验");
  return event ? { ...event } : null;
});
const timeline = computed(() => {
  revision();
  const work = record.value;
  if (!work) return [];
  return [
    ...events()
      .filter((item) => item.workId === work.id)
      .map((item) => ({ time: item.time, text: personName(item.personId) + "\u3000" + item.title })),
    { time: "09:12:33", text: personName(work.leader) + " 开始设备检查" },
    { time: work.start, text: work.members.length + " 人到达作业区域，开始监护" },
  ];
});
const supervisorName = computed(() => db.person(record.value?.supervisor)?.name || "");

function memberOf(id) {
  return db.person(id);
}

function roleOf(id) {
  if (id === record.value?.supervisor) return "现场监护人";
  if (id === record.value?.leader) return "作业负责人";
  return "作业人员";
}

function openRisk() {
  const work = record.value;
  if (!work) return;
  openModal({
    title: "来源风险信息 · " + work.name,
    view: WorkRiskInfo,
    props: { workId: work.id },
    footer: ModalClose,
  });
}

function openRecords() {
  const work = record.value;
  if (!work) return;
  openModal({ title: "作业现场记录", view: WorkRecords, props: { workId: work.id } });
}
</script>

<template>
  <MissingRecord v-if="!record" />
  <template v-else>
    <PageHeading>
      <template #title>
        <a class="text-link" href="#/works"><AppIcon name="arrow-left-line" /> 返回作业列表</a>　{{ record.name }}　<AppTag>进行中</AppTag>
      </template>
      <template #actions>
        <AppStatCards :items="stats" variant="mini" />
      </template>
    </PageHeading>
    <div class="row muted" style="margin-bottom:18px">
      工作票编号　{{ record.id }}　<AppTag color="muted">只读（来源：作业管理系统）</AppTag>
      <span class="spacer"></span>
      负责人　{{ personName(record.leader) }}　|　监护人　{{ personName(record.supervisor) }}　|　作业时间　{{ record.date }} {{ record.start }} – {{ record.end }}
    </div>
    <div class="grid cols-2">
      <div class="stack">
        <VideoFrame v-if="camera" :person-id="camera.id" controls frame-class="work-media" />
        <AppEmpty v-else text="作业暂无成员" />
        <div class="row">
          <AppButton
            v-for="(pid, index) in record.members"
            :key="pid"
            :tone="session.person === pid ? 'active' : ''"
            @click="session.person = pid"
          >镜头 {{ index + 1 }} · {{ memberOf(pid)?.name }}</AppButton>
        </div>
        <AppPanel :title="'作业人员与装备状态（' + record.members.length + ' 人）'">
          <AppTable :columns="['姓名', '岗位', '三类装备状态（安全帽 / 安全带 / 智能手表）', '位置', '最后上报', '操作']" :empty="!record.members.length">
            <tr v-for="pid in record.members" :key="pid">
              <td>
                <div class="person-cell"><PersonAvatar :person="memberOf(pid)" photo />{{ personName(pid) }}</div>
              </td>
              <td><AppTag>{{ roleOf(pid) }}</AppTag></td>
              <td><DeviceStrip :person-id="pid" /></td>
              <td>{{ memberOf(pid)?.area }}</td>
              <td>{{ memberOf(pid)?.updated }}</td>
              <td>
                <div class="inline-buttons">
                  <a class="btn small" :href="'#/tracks/' + pid">查看轨迹</a>
                  <AppButton tone="small" @click="runGuarded(() => callPerson(pid))">发起对讲</AppButton>
                </div>
              </td>
            </tr>
          </AppTable>
        </AppPanel>
      </div>
      <div class="stack">
        <AppPanel>
          <template #title>
            <template v-if="currentEvent"><AppIcon name="alarm-warning-fill" color="yellow" />　{{ currentEvent.title }}</template>
            <template v-else>事件状态</template>
          </template>
          <template v-if="currentEvent" #extra>
            <AppTag color="yellow">{{ currentEvent.status }}</AppTag>
          </template>
          <template v-if="currentEvent">
            <dl class="info compact">
              <dt>涉及人员</dt>
              <dd>{{ personName(currentEvent.personId) }}</dd>
              <dt>设备编号</dt>
              <dd>{{ currentEvent.deviceId }}</dd>
              <dt>发生时间</dt>
              <dd>{{ currentEvent.date }} {{ currentEvent.time }}</dd>
              <dt>事件描述</dt>
              <dd>{{ currentEvent.title }}，需联系现场核验。</dd>
            </dl>
            <div class="form-actions">
              <a class="btn primary" :href="'#/event/' + currentEvent.id">查看事件详情</a>
              <AppButton @click="runGuarded(() => callPerson(record.supervisor))">联系监护人（{{ supervisorName }}）</AppButton>
            </div>
          </template>
          <AppStatus v-else>暂无待核验事项</AppStatus>
        </AppPanel>
        <AppPanel title="作业区域示意">
          <template #extra>厂区示意 · 非实测</template>
          <div style="height:220px"><PlantMap :person="camera?.id || ''" :legend="false" /></div>
          <div class="detail-section">
            <h3>来源风险提示　<AppTag color="yellow">来源摘要（示例）</AppTag></h3>
            <p class="note">本作业存在高处作业、受限空间临近、热表面等风险，请按作业方案落实安全防护措施。</p>
            <AppButton tone="plain blue" @click="openRisk">查看完整风险信息 ›</AppButton>
          </div>
        </AppPanel>
        <AppPanel title="现场记录">
          <template #extra>
            <AppButton tone="small" @click="openRecords">全部记录</AppButton>
          </template>
          <div class="timeline">
            <div v-for="(item, index) in timeline" :key="index" class="timeline-item"><time>{{ item.time }}</time>{{ item.text }}</div>
          </div>
        </AppPanel>
      </div>
    </div>
  </template>
</template>
