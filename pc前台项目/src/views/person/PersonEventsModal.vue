<script setup>
import { computed } from "vue";
import AppButton from "@/components/ui/AppButton.vue";
import AppTable from "@/components/ui/AppTable.vue";
import AppTag from "@/components/ui/AppTag.vue";
import { go } from "@/lib/actions";
import { events, revision } from "@/lib/queries";
import { closeModal } from "@/stores/modal";

const props = defineProps({
  personId: { type: String, default: "" },
});

const columns = ["事件", "状态", "操作"];

const rows = computed(() => {
  revision();
  return events().filter((item) => item.personId === props.personId);
});

function openEvent(id) {
  closeModal();
  go("event/" + id);
}
</script>

<template>
  <AppTable :columns="columns" :empty="!rows.length">
    <tr v-for="item in rows" :key="item.id">
      <td>{{ item.title }}</td>
      <td><AppTag>{{ item.status }}</AppTag></td>
      <td><AppButton tone="small" @click="openEvent(item.id)">查看</AppButton></td>
    </tr>
  </AppTable>
</template>
