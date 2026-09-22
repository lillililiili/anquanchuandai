<script setup>
import { computed, reactive, watch } from "vue";
import AppField from "@/components/ui/AppField.vue";
import AppIcon from "@/components/ui/AppIcon.vue";
import AppInput from "@/components/ui/AppInput.vue";
import AppPanel from "@/components/ui/AppPanel.vue";
import AppSelect from "@/components/ui/AppSelect.vue";
import AppStatCards from "@/components/ui/AppStatCards.vue";
import AppStatus from "@/components/ui/AppStatus.vue";
import AppTable from "@/components/ui/AppTable.vue";
import FilterBar from "@/components/layout/FilterBar.vue";
import LocationTabs from "@/components/layout/LocationTabs.vue";
import PageHeading from "@/components/layout/PageHeading.vue";
import PlantMap from "@/components/domain/PlantMap.vue";
import { db } from "@/mock/runtime";
import { filtersOf, session } from "@/stores/session";
import { people, revision, search, works } from "@/lib/queries";

const draft = reactive({ q: "", workId: "" });

function readDraft() {
  const query = filtersOf("location");
  draft.q = query.q || "";
  draft.workId = query.workId || "";
}

readDraft();

const layers = [
  { key: "people", label: "人员" },
  { key: "areas", label: "作业区域" },
  { key: "fences", label: "电子围栏" },
];

const workOptions = computed(() => {
  revision();
  return [["", "全部作业"], ...works().map((work) => [work.id, work.name])];
});

const locatedPeople = computed(() => {
  revision();
  const query = filtersOf("location");
  return people().filter((person) => {
    const devices = db.currentDevices(person.id).map((device) => device.id).join(" ");
    const inWork = !query.workId || db.currentWork(person.id)?.id === query.workId;
    return search(person.name + " " + devices, query.q) && inWork;
  });
});

watch(
  locatedPeople,
  (list) => {
    const next = list.find((person) => person.id === session.person) || list[0];
    if (next && session.person !== next.id) session.person = next.id;
  },
  { immediate: true },
);

const focus = computed(() => {
  revision();
  return locatedPeople.value.find((person) => person.id === session.person) || locatedPeople.value[0] || null;
});

const personIds = computed(() => {
  revision();
  return locatedPeople.value.map((person) => person.id);
});

const cards = computed(() => {
  revision();
  const list = locatedPeople.value;
  const visible = list.filter((person) => db.locationValid(person.id)).length;
  return [
    { icon: "user-line", label: "当班人员", value: list.length, unit: "", color: "cyan" },
    { icon: "map-pin-line", label: "位置可查看", value: visible, unit: "", color: "cyan" },
    { icon: "alarm-warning-line", label: "位置待核验", value: list.length - visible, unit: "", color: "yellow" },
  ];
});

function helmetId(personId) {
  return db.currentDevices(personId).find((device) => device.type === "H")?.id || "未绑定";
}

function applyFilters() {
  session.filters.location = { q: draft.q, workId: draft.workId };
}

function resetFilters() {
  session.filters.location = {};
  draft.q = "";
  draft.workId = "";
}

function choose(id) {
  session.person = id;
}
</script>

<template>
  <PageHeading title="实时定位" subtitle="按人员查看关联安全帽位置">
    <template #actions>
      <AppStatCards :items="cards" variant="mini" />
    </template>
  </PageHeading>
  <LocationTabs />
  <div class="location-layout">
    <AppPanel title="当班人员">
      <FilterBar @submit="applyFilters" @reset="resetFilters">
        <div class="searchbox">
          <AppIcon name="search-line" />
          <AppInput v-model="draft.q" name="q" placeholder="姓名 / 安全帽编号" />
        </div>
        <AppField label="作业分组">
          <AppSelect v-model="draft.workId" name="workId" :options="workOptions" />
        </AppField>
      </FilterBar>
      <AppTable :columns="['姓名', '安全帽编号', '作业区域', '状态']" :empty="!locatedPeople.length">
        <tr
          v-for="person in locatedPeople"
          :key="person.id"
          :class="{ selected: person.id === session.person }"
          @click="choose(person.id)"
        >
          <td><AppIcon name="user-fill" />　{{ person.name }}</td>
          <td>{{ helmetId(person.id) }}</td>
          <td>{{ db.locationValid(person.id) ? person.area : "位置待核验" }}</td>
          <td>
            <AppStatus :color="db.locationValid(person.id) ? 'green' : 'yellow'">
              {{ db.locationValid(person.id) ? "在线" : "待核验" }}
            </AppStatus>
          </td>
        </tr>
      </AppTable>
    </AppPanel>
    <PlantMap :popup="!!focus" :person-ids="personIds" />
  </div>
  <div class="layer-controls">
    <label v-for="layer in layers" :key="layer.key">
      <input v-model="session.layers[layer.key]" type="checkbox" />{{ layer.label }}
    </label>
  </div>
  <p class="note"><AppIcon name="information-line" />人员位置由关联安全帽提供；位置滞后或缺失需现场核验，不表示室内精度。</p>
</template>
