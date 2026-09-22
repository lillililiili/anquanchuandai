<script setup>
import { computed } from "vue";
import AppButton from "@/components/ui/AppButton.vue";
import AppTable from "@/components/ui/AppTable.vue";
import { closeModal } from "@/stores/modal";
import { go } from "@/lib/actions";
import { events, personName, revision } from "@/lib/queries";

const props = defineProps({
  workId: { type: String, default: "" },
});

const rows = computed(() => {
  revision();
  return events().filter((item) => item.workId === props.workId);
});

function openEvent(id) {
  closeModal();
  go("event/" + id);
}
</script>

<template>
  <AppTable :columns="['时间', '人员', '事件', '操作']" :empty="!rows.length">
    <tr v-for="item in rows" :key="item.id">
      <td>{{ item.date }} {{ item.time }}</td>
      <td>{{ personName(item.personId) }}</td>
      <td>{{ item.title }}</td>
      <td><AppButton tone="small" @click="openEvent(item.id)">查看</AppButton></td>
    </tr>
  </AppTable>
</template>
