<script setup>
import { computed } from "vue";
import AppEmpty from "@/components/ui/AppEmpty.vue";
import AppTable from "@/components/ui/AppTable.vue";
import { db } from "@/mock/runtime";
import { revision } from "@/lib/queries";
import { isSimulatedVital } from "@/lib/sample-data";
import { vitalValue, bloodPressure } from './vital-values';

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
  <p class="note">标记为“模拟数据”的记录仅供演示，非实时测量。历史记录保留观测时的人员和设备归属。</p>
  <AppTable :rows="rows" v-slot="{ rows: pageRows }" v-if="rows.length" table-class="compact" :columns="columns">
    <tr v-for="item in pageRows" :key="item.id">
      <td>{{ item.personName }}<small>{{ item.deviceId }}</small><small>{{ isSimulatedVital(item) ? '模拟数据' : '设备观测' }}</small></td>
      <td>{{ item.observedAt }}<small>{{ item.receivedAt }}</small></td>
      <td>{{ vitalValue(item.heartRate) ?? '—' }} bpm</td>
      <td>{{ vitalValue(item.oxygen) ?? '—' }} %</td>
      <td>{{ vitalValue(item.temperature, 1) ?? '—' }} °C</td>
      <td>{{ bloodPressure(item) ?? '—' }} mmHg</td>
    </tr>
  </AppTable>
  <AppEmpty v-else text="暂无历史观测记录" />
</template>
