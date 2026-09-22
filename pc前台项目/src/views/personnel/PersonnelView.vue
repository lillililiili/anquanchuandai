<script setup>
import { computed, reactive, watch } from "vue";
import PageHeading from "@/components/layout/PageHeading.vue";
import FilterBar from "@/components/layout/FilterBar.vue";
import AppButton from "@/components/ui/AppButton.vue";
import AppEmpty from "@/components/ui/AppEmpty.vue";
import AppField from "@/components/ui/AppField.vue";
import AppIcon from "@/components/ui/AppIcon.vue";
import AppInput from "@/components/ui/AppInput.vue";
import AppSelect from "@/components/ui/AppSelect.vue";
import AppStatus from "@/components/ui/AppStatus.vue";
import AppTable from "@/components/ui/AppTable.vue";
import AppTabs from "@/components/ui/AppTabs.vue";
import AppTag from "@/components/ui/AppTag.vue";
import DeviceStrip from "@/components/domain/DeviceStrip.vue";
import PersonAvatar from "@/components/domain/PersonAvatar.vue";
import VideoFrame from "@/components/domain/VideoFrame.vue";
import { db } from "@/mock/runtime";
import { filtersOf, session } from "@/stores/session";
import { events, people, personName, revision, search, statusColor } from "@/lib/queries";
import { callPerson, runGuarded } from "@/lib/actions";

const columns = ["序号", "人员信息", "所属区域", "当前作业", "装备状态", "最近更新时间", "操作"];
const workStatusOptions = [
  ["", "全部"],
  ["assigned", "作业中"],
  ["idle", "待分配"],
];
const detailTabs = ["人员信息", "装备信息", "作业信息", "事件信息"].map((label) => ({ id: label, label }));

const saved = filtersOf("personnel");
const draft = reactive({
  q: saved.q || "",
  team: saved.team || "",
  workStatus: saved.workStatus || "",
});

const teamOptions = computed(() => {
  revision();
  const teams = [...new Set(people().map((person) => person.team))];
  return [["", "全部"], ...teams.map((team) => [team, team])];
});

const rows = computed(() => {
  revision();
  const query = session.filters.personnel || {};
  return people()
    .map((person) => {
      const devices = db.currentDevices(person.id);
      return {
        person,
        devices,
        work: db.currentWork(person.id),
        helmet: devices.find((device) => device.type === "H") || null,
      };
    })
    .filter((row) => {
      const identity = `${row.person.name} ${row.person.id} ${row.devices.map((device) => device.id).join(" ")}`;
      const teamOk = !query.team || row.person.team === query.team;
      const statusOk = !query.workStatus || (query.workStatus === "assigned" ? !!row.work : !row.work);
      return search(identity, query.q) && teamOk && statusOk;
    });
});

const current = computed(() => rows.value.find((row) => row.person.id === session.person) || rows.value[0] || null);

const pending = computed(() => {
  revision();
  const id = current.value?.person.id;
  if (!id) return [];
  return events().filter((item) => item.personId === id && item.status !== "已核验");
});

const related = computed(() => pending.value[0] || null);

watch(
  () => current.value?.person.id,
  (id) => {
    if (id && session.person !== id) session.person = id;
  },
  { immediate: true },
);

function applyFilters() {
  session.filters.personnel = {
    q: draft.q,
    team: draft.team,
    workStatus: draft.workStatus,
  };
}

function resetFilters() {
  session.filters.personnel = {};
  draft.q = "";
  draft.team = "";
  draft.workStatus = "";
}

function selectPerson(id) {
  session.person = id;
  session.hidePerson = false;
}

function talk() {
  const id = current.value?.person.id;
  if (!id) return;
  runGuarded(() => callPerson(id));
}
</script>

<template>
  <div class="split-detail" :style="session.hidePerson ? 'grid-template-columns:1fr' : null">
    <div>
      <PageHeading title="当班人员与装备" subtitle="以人员查看三类装备与当前作业" />
      <FilterBar @submit="applyFilters" @reset="resetFilters">
        <div class="searchbox">
          <AppIcon name="search-line" />
          <AppInput v-model="draft.q" name="q" placeholder="搜索姓名或人员编号" />
        </div>
        <AppField label="班组">
          <AppSelect v-model="draft.team" name="team" :options="teamOptions" />
        </AppField>
        <AppField label="作业状态">
          <AppSelect v-model="draft.workStatus" name="workStatus" :options="workStatusOptions" />
        </AppField>
      </FilterBar>
      <div class="panel">
        <AppTable table-class="personnel-list" :columns="columns" :empty="!rows.length">
          <template #head>
            <th>序号</th>
            <th>人员信息</th>
            <th>所属区域</th>
            <th>当前作业</th>
            <th>装备状态<br /><small>（安全帽 / 安全带 / 智能手表）</small></th>
            <th>最近更新时间</th>
            <th>操作</th>
          </template>
          <tr
            v-for="(row, index) in rows"
            :key="row.person.id"
            data-action="select-person"
            :data-id="row.person.id"
            :class="{ selected: current && row.person.id === current.person.id }"
            @click="selectPerson(row.person.id)"
          >
            <td>{{ index + 1 }}</td>
            <td>
              <div class="person-cell">
                <PersonAvatar :person="row.person" />
                <div>
                  <strong>{{ row.person.name }}</strong>
                  <small>{{ row.helmet?.id || "未绑定" }} | {{ row.person.team }}</small>
                </div>
              </div>
            </td>
            <td>{{ row.person.area }}</td>
            <td>
              {{ row.work?.name || "待分配" }}<small>{{ row.work ? "（监护人：" + personName(row.work.supervisor) + "）" : "" }}</small>
            </td>
            <td><DeviceStrip :person-id="row.person.id" /></td>
            <td>{{ row.person.updated }}</td>
            <td><a class="btn small" :href="'#/person/' + row.person.id" @click.stop>查看详情</a></td>
          </tr>
        </AppTable>
      </div>
    </div>
    <aside
      v-if="!session.hidePerson"
      :class="['panel', { 'person-detail-focused': session.personTab !== '人员信息' }]"
      :data-detail-tab="session.personTab"
    >
      <div class="panel-body">
        <template v-if="current">
          <div class="detail-heading">
            <PersonAvatar :person="current.person" />
            <div>
              <h3>{{ current.person.name }} <small>{{ current.helmet?.id || "未绑定" }}</small></h3>
              <small>{{ current.person.team }}　|　手机：{{ current.person.phone || "—" }}</small>
            </div>
            <AppButton tone="icon-only" icon="close-line" aria-label="关闭人员详情" @click="session.hidePerson = true" />
          </div>
          <AppTabs v-model="session.personTab" :tabs="detailTabs" />
          <dl v-if="session.personTab === '人员信息'" class="info compact">
            <dt>所属区域</dt>
            <dd>{{ current.person.area }}</dd>
            <dt>当前作业</dt>
            <dd>{{ current.work?.name || "待分配" }}</dd>
            <dt>当前监护人</dt>
            <dd>{{ personName(current.work?.supervisor) }}</dd>
            <dt>当前负责人</dt>
            <dd>{{ personName(current.work?.leader) }}</dd>
          </dl>
          <div v-if="session.personTab === '人员信息' || session.personTab === '装备信息'" class="detail-section">
            <h3>装备状态 <small>（以领用记录为准）</small></h3>
            <DeviceStrip :person-id="current.person.id" />
            <a class="text-link" :href="'#/person/' + current.person.id">查看领用记录 ›</a>
          </div>
          <div v-if="session.personTab === '人员信息' || session.personTab === '作业信息'" class="detail-section">
            <h3>关联作业</h3>
            <template v-if="current.work">
              <b>{{ current.work.name }}</b>
              <p><small>{{ current.work.id }}</small></p>
              <p>作业区域　{{ current.work.area }}</p>
              <p>监护人　{{ personName(current.work.supervisor) }}</p>
              <a class="text-link" :href="'#/work/' + current.work.id">查看作业详情 ›</a>
            </template>
            <AppEmpty v-else text="待分配作业" />
          </div>
          <div v-if="session.personTab === '人员信息' || session.personTab === '事件信息'" class="detail-section">
            <h3>待核验事件（{{ pending.length }}）</h3>
            <template v-if="related">
              <a :href="'#/event/' + related.id"><AppIcon name="error-warning-fill" color="yellow" />　{{ related.title }}</a>
              <p><AppTag :color="statusColor(related.status)">{{ related.status }}</AppTag></p>
            </template>
            <AppStatus v-else>暂无待核验事件</AppStatus>
          </div>
          <div class="detail-section detail-media">
            <div class="grid equal">
              <div class="detail-video">
                <h3>现场视频</h3>
                <a :href="'#/single/' + current.person.id"><VideoFrame :person-id="current.person.id" /></a>
              </div>
              <div class="detail-call">
                <h3>语音对讲</h3>
                <AppButton tone="primary wide" icon="mic-line" @click="talk">发起对讲</AppButton>
                <small>与 {{ current.person.name }} 进行模拟通话</small>
              </div>
            </div>
          </div>
        </template>
        <AppEmpty v-else />
      </div>
    </aside>
  </div>
</template>
