<script setup>
import { computed } from "vue";
import AppButton from "@/components/ui/AppButton.vue";
import AppTable from "@/components/ui/AppTable.vue";
import AppTag from "@/components/ui/AppTag.vue";
import WorkMembersForm from "./WorkMembersForm.vue";
import { db } from "@/mock/runtime";
import { openModal } from "@/stores/modal";
import { toast } from "@/stores/notify";
import { revision, works } from "@/lib/queries";

const rows = computed(() => {
  revision();
  return works();
});

function edit(id) {
  const work = db.work(id);
  if (!work) {
    toast("请选择作业", true);
    return;
  }
  openModal({
    title: "调整作业成员 · " + work.name,
    view: WorkMembersForm,
    props: { workId: id },
  });
}
</script>

<template>
  <p class="muted">选择已有来源作业，维护监护成员和负责人。</p>
  <AppTable :columns="['作业名称', '工作票号', '状态', '操作']" :empty="!rows.length">
    <tr v-for="work in rows" :key="work.id">
      <td>{{ work.name }}</td>
      <td>{{ work.id }}</td>
      <td><AppTag>{{ work.synced ? "已关联" : "待同步" }}</AppTag></td>
      <td><AppButton tone="small primary" @click="edit(work.id)">关联与配置</AppButton></td>
    </tr>
  </AppTable>
</template>
