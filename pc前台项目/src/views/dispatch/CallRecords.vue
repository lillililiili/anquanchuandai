<script setup>
import { computed } from "vue";
import AppButton from "@/components/ui/AppButton.vue";
import AppTable from "@/components/ui/AppTable.vue";
import AppTag from "@/components/ui/AppTag.vue";
import CallRecordDetail from "./CallRecordDetail.vue";
import { db } from "@/mock/runtime";
import { session } from "@/stores/session";
import { openModal } from "@/stores/modal";
import { personName, revision } from "@/lib/queries";

const rows = computed(() => {
  revision();
  return db.state.calls.filter((call) => call.station === session.station);
});

function names(call) {
  return (call.members || []).map((id) => personName(id)).join("、");
}

function openDetail(id) {
  openModal({
    title: "通信记录详情",
    view: CallRecordDetail,
    props: { callId: id },
  });
}
</script>

<template>
  <AppTable :columns="['时间', '类型', '参与人员', '状态', '操作']" :empty="!rows.length">
    <tr v-for="call in rows" :key="call.id">
      <td>{{ call.time }}</td>
      <td>{{ call.kind }}</td>
      <td>{{ names(call) }}</td>
      <td><AppTag>{{ call.status }}</AppTag></td>
      <td><AppButton tone="small" @click="openDetail(call.id)">详情</AppButton></td>
    </tr>
  </AppTable>
</template>
