<script setup>
import { computed } from "vue";
import AppEmpty from "@/components/ui/AppEmpty.vue";
import AppTable from "@/components/ui/AppTable.vue";
import { db } from "@/mock/runtime";
import { revision } from "@/lib/queries";

const props = defineProps({
  personId: { type: String, default: "" },
});

const columns = ["观测人员 / 手表", "观测时间 / 接收时间", "心率", "血氧", "体温", "血压"];

const rows = computed(() => {
  revision();
  return db.vitalHistory(props.personId);
});
</script>

<template>
  <p class="note">预置观测，非实时测量；手表能力待确认。历史记录保留观测时的人员和设备归属。</p>
  <AppTable v-if="rows.length" table-class="compact" :columns="columns">
    <tr v-for="item in rows" :key="item.id">
      <td>{{ item.personName }}<small>{{ item.deviceId }}</small></td>
      <td>{{ item.observedAt }}<small>{{ item.receivedAt }}</small></td>
      <td>{{ item.heartRate }} bpm</td>
      <td>{{ item.oxygen }} %</td>
      <td>{{ Number(item.temperature).toFixed(1) }} °C</td>
      <td>{{ item.systolic }} / {{ item.diastolic }} mmHg</td>
    </tr>
  </AppTable>
  <AppEmpty v-else text="暂无历史观测记录" />
</template>
