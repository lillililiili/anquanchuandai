<script setup>
import { computed, reactive, ref, watchEffect } from "vue";
import AppButton from "@/components/ui/AppButton.vue";
import AppEmpty from "@/components/ui/AppEmpty.vue";
import AppField from "@/components/ui/AppField.vue";
import AppIcon from "@/components/ui/AppIcon.vue";
import AppInput from "@/components/ui/AppInput.vue";
import AppPagination from "@/components/ui/AppPagination.vue";
import AppPanel from "@/components/ui/AppPanel.vue";
import AppSelect from "@/components/ui/AppSelect.vue";
import AppStatCards from "@/components/ui/AppStatCards.vue";
import AppTable from "@/components/ui/AppTable.vue";
import AppTag from "@/components/ui/AppTag.vue";
import FilterBar from "@/components/layout/FilterBar.vue";
import PageHeading from "@/components/layout/PageHeading.vue";
import PlantMap from "@/components/domain/PlantMap.vue";
import VideoFrame from "@/components/domain/VideoFrame.vue";
import { DATE } from "@/mock/data";
import { db } from "@/mock/runtime";
import { session, filtersOf } from "@/stores/session";
import { events, personName, revision, search, statusColor } from "@/lib/queries";
import { toast } from "@/stores/notify";

const typeOptions = [["", "全部"], "人员求助", "电子围栏", "设备通信", "低电量", "位置异常", "安全带挂接", "生命体征"];
const statusOptions = [["", "全部"], "待现场核验", "待认领", "处理中", "已核验"];
const columns = ["事件编号", "类型", "人员", "设备编号", "发生时间", "状态", "操作"];

const stored = filtersOf("alarms");
const draft = reactive({
  q: stored.q || "",
  date: stored.date || DATE,
  type: stored.type || "",
  status: stored.status || "",
});

function urgency(item) {
  if (item.type === "人员求助" && item.status !== "已核验") return 0;
  if (item.status === "待认领") return 1;
  if (item.status === "待现场核验") return 2;
  if (item.status === "处理中") return 3;
  return 4;
}

const alarms = computed(() => {
  revision();
  const query = filtersOf("alarms");
  return events()
    .filter(
      (item) =>
        search(item.deviceId, query.q) &&
        (!query.date || item.date === query.date) &&
        (!query.type || item.type === query.type) &&
        (!query.status || item.status === query.status),
    )
    .sort((a, b) => urgency(a) - urgency(b) || b.time.localeCompare(a.time));
});

const openSos = computed(() => alarms.value.filter((item) => item.type === "人员求助" && item.status !== "已核验"));
const leadSos = computed(() => openSos.value[0] || null);
const sosSelected = computed(() => selectedAlarm.value?.type === "人员求助" && selectedAlarm.value?.status !== "已核验");

const noticedSos = ref(false);
watchEffect(() => {
  if (noticedSos.value || !leadSos.value) return;
  session.event = leadSos.value.id;
  noticedSos.value = true;
});

watchEffect(() => {
  const current = alarms.value.find((item) => item.id === session.event) || alarms.value[0];
  if (current && session.event !== current.id) session.event = current.id;
});

const selectedAlarm = computed(() => {
  revision();
  return alarms.value.find((item) => item.id === session.event) || null;
});

const selectedWork = computed(() => {
  revision();
  return selectedAlarm.value ? db.work(selectedAlarm.value.workId) : null;
});

const summaryCards = computed(() => {
  revision();
  const count = (status) => alarms.value.filter((item) => item.status === status).length;
  return [
    { icon: "alarm-warning-line", label: "待现场核验", value: count("待现场核验"), unit: "", color: "yellow" },
    { icon: "file-list-3-line", label: "待认领", value: count("待认领"), unit: "", color: "cyan" },
    { icon: "settings-3-line", label: "处理中", value: count("处理中"), unit: "", color: "cyan" },
  ];
});

function applyFilters() {
  session.filters.alarms = {
    q: draft.q,
    date: draft.date,
    type: draft.type,
    status: draft.status,
  };
  if (!draft.date) draft.date = DATE;
}

function resetFilters() {
  session.filters.alarms = {};
  draft.q = "";
  draft.date = DATE;
  draft.type = "";
  draft.status = "";
}

function selectAlarm(event, id) {
  if (event.target.closest("a, button")) return;
  session.event = id;
}

function claimAlarm(id) {
  try {
    db.claim(id);
    toast("事件已认领");
  } catch (error) {
    toast(error.message || "操作失败", true);
  }
}

function typeIcon(item) {
  return (
    {
      位置异常: "map-pin-line",
      人员求助: "alarm-warning-fill",
      电子围栏: "shape-line",
      低电量: "battery-low-line",
      安全带挂接: "link-unlink",
      生命体征: "heart-pulse-line",
    }[item.type] || "alarm-warning-fill"
  );
}

function rowClass(item) {
  return {
    selected: item.id === session.event,
    "is-sos": item.type === "人员求助" && item.status !== "已核验",
    "is-hot": item.status === "待认领" || item.status === "待现场核验",
    "is-live": item.status === "处理中",
    "is-done": item.status === "已核验",
  };
}
</script>

<template>
  <div class="split-detail">
    <div>
      <PageHeading title="告警与核验" subtitle="设备异常与现场核验协同">
        <template #actions>
          <AppStatCards :items="summaryCards" variant="mini" />
        </template>
      </PageHeading>
      <a v-if="leadSos" class="sos-call" :href="'#/event/' + leadSos.id">
        <span class="sos-call-mark">SOS</span>
        <span class="sos-call-copy">
          <strong>{{ leadSos.snapshot.personName }} 正在求助</strong>
          <small>{{ leadSos.title }} · {{ leadSos.deviceId }} · {{ leadSos.time }}<template v-if="openSos.length > 1"> · 另有 {{ openSos.length - 1 }} 起 SOS</template></small>
        </span>
        <span class="sos-call-go">立即响应</span>
      </a>
      <FilterBar data-form="filters" @submit="applyFilters" @reset="resetFilters">
        <AppField label="设备编号">
          <AppInput v-model="draft.q" name="q" placeholder="请输入设备编号" />
        </AppField>
        <AppField label="日期">
          <AppInput v-model="draft.date" name="date" type="date" />
        </AppField>
        <AppField label="事件类型">
          <AppSelect v-model="draft.type" name="type" :options="typeOptions" />
        </AppField>
        <AppField label="核验状态">
          <AppSelect v-model="draft.status" name="status" :options="statusOptions" />
        </AppField>
      </FilterBar>
      <div class="panel alarms-table">
        <AppTable :columns="columns" :empty="!alarms.length">
          <tr
            v-for="item in alarms"
            :key="item.id"
            data-action="select-event"
            :data-id="item.id"
            :class="rowClass(item)"
            @click="selectAlarm($event, item.id)"
          >
            <td>{{ item.id }}</td>
            <td>
              <AppIcon :name="typeIcon(item)" :color="item.type === '人员求助' ? 'red' : statusColor(item.status)" />
              <AppTag v-if="item.type === '人员求助'" color="red">SOS</AppTag>
              {{ item.title }}
            </td>
            <td>{{ item.snapshot.personName }}</td>
            <td>{{ item.deviceId }}</td>
            <td>{{ item.time }}</td>
            <td><AppTag :color="statusColor(item.status)">{{ item.status }}</AppTag></td>
            <td>
              <a v-if="item.type === '人员求助' && item.status !== '已核验'" class="btn small danger sos-row-go" :href="'#/event/' + item.id" @click.stop>立即响应</a>
              <AppButton v-else-if="item.status === '待认领'" tone="small primary" @click.stop="claimAlarm(item.id)">马上认领</AppButton>
              <a v-else-if="item.status !== '已核验'" class="btn small primary" :href="'#/event/' + item.id" @click.stop>去核验</a>
              <a v-else class="btn small" :href="'#/event/' + item.id" @click.stop>查看</a>
            </td>
          </tr>
        </AppTable>
      </div>
      <AppPagination :total="alarms.length" />
    </div>
    <AppPanel title="事件摘要" :extra-class="sosSelected ? 'alarm-detail is-sos' : 'alarm-detail'">
      <template v-if="selectedAlarm">
        <div v-if="sosSelected" class="sos-now"><b>SOS</b><span>{{ selectedAlarm.snapshot.personName }} 正在求助，请立即响应</span></div>
        <h3><AppIcon :name="sosSelected ? 'alarm-warning-fill' : 'alarm-warning-line'" :color="sosSelected ? 'red' : 'yellow'" />　{{ selectedAlarm.title }}</h3>
        <dl class="info compact">
          <dt>人员 · 设备</dt>
          <dd>{{ selectedAlarm.snapshot.personName }} · {{ selectedAlarm.deviceId }}</dd>
          <dt>作业名称</dt>
          <dd>{{ selectedAlarm.snapshot.workName }}</dd>
          <dt>作业编号</dt>
          <dd>{{ selectedAlarm.workId || "—" }}</dd>
          <dt>当前监护人</dt>
          <dd>{{ personName(selectedWork?.supervisor) }}</dd>
          <dt>发生时间</dt>
          <dd>{{ selectedAlarm.date }} {{ selectedAlarm.time }}</dd>
        </dl>
        <div v-if="selectedAlarm.type === '设备通信' || selectedAlarm.type === '安全带挂接'" class="warning-box" style="margin-top:15px">
          <h3 style="font-size:15px">连接或挂接信号不直接判定穿戴违规</h3>
          <small>平台仅进行监测、通信、核验与记录，不作为违规判定依据。</small>
        </div>
        <div class="detail-section">
          <h3>事件来源</h3>
          <dl class="info compact">
            <dt>原安监事件</dt>
            <dd>{{ selectedAlarm.externalId }}</dd>
            <dt>当前状态</dt>
            <dd class="blue">{{ selectedAlarm.externalStatus }}</dd>
          </dl>
        </div>
        <div class="detail-section">
          <h3>现场位置</h3>
          <PlantMap :person="selectedAlarm.personId" :legend="false" />
        </div>
        <div class="detail-section">
          <h3>现场视频</h3>
          <a :href="'#/single/' + selectedAlarm.personId"><VideoFrame :person-id="selectedAlarm.personId" /></a>
        </div>
        <div class="form-actions">
          <a :class="['btn', 'wide', sosSelected ? 'danger sos-action' : 'primary']" :href="'#/event/' + selectedAlarm.id">{{ sosSelected ? "立即响应 SOS" : "进入现场核验" }}</a>
        </div>
        <p class="note cyan"><AppIcon name="checkbox-circle-fill" />摘要回传（示例） · {{ selectedAlarm.verification ? "核验记录已提交" : "核验记录未提交" }}</p>
      </template>
      <AppEmpty v-else />
    </AppPanel>
  </div>
</template>
