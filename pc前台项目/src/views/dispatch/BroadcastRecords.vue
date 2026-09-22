<script setup>
import { computed } from "vue";
import AppTable from "@/components/ui/AppTable.vue";
import AppTag from "@/components/ui/AppTag.vue";
import { db } from "@/mock/runtime";
import { session } from "@/stores/session";
import { personName, revision } from "@/lib/queries";

const rows = computed(() => {
  revision();
  return db.state.broadcasts.filter((item) => item.station === session.station);
});

function names(item) {
  return (item.members || []).map((id) => personName(id)).join("、");
}
</script>

<template>
  <AppTable :columns="['时间', '分组', '内容', '接收人员', '状态']" :empty="!rows.length">
    <tr v-for="item in rows" :key="item.id">
      <td>{{ item.time }}</td>
      <td>{{ item.groupName }}</td>
      <td>{{ item.text }}</td>
      <td>{{ names(item) }}</td>
      <td><AppTag color="green">{{ item.status }}</AppTag></td>
    </tr>
  </AppTable>
</template>
