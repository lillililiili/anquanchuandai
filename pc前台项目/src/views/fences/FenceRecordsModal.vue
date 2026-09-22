<script setup>
import { computed, ref } from "vue";
import AppButton from "@/components/ui/AppButton.vue";
import AppField from "@/components/ui/AppField.vue";
import AppSelect from "@/components/ui/AppSelect.vue";
import AppTable from "@/components/ui/AppTable.vue";
import AppTag from "@/components/ui/AppTag.vue";
import { db } from "@/mock/runtime";
import { session } from "@/stores/session";
import { toast } from "@/stores/notify";
import { people, revision } from "@/lib/queries";

const records = computed(() => {
  revision();
  return db.state.fenceRecords.filter((item) => item.station === session.station);
});

const roster = computed(() => {
  revision();
  return people().map((person) => [person.id, person.name]);
});

const targets = [
  ["inside", "锅炉区域内"],
  ["outside", "厂区道路外侧"],
];

const personId = ref(roster.value.some((item) => item[0] === session.person) ? session.person : roster.value[0]?.[0] || "");
const target = ref("outside");
const error = ref("");

function submit() {
  error.value = "";
  try {
    db.movePerson(personId.value, target.value === "inside" ? [35, 45] : [8, 8]);
    toast("位置已更新，围栏进出条件已检查");
  } catch (err) {
    error.value = err.message || "操作失败";
  }
}
</script>

<template>
  <AppTable :columns="['时间', '围栏', '人员', '方向']" :empty="!records.length">
    <tr v-for="item in records" :key="item.id">
      <td>{{ item.time }}</td>
      <td>{{ item.fenceName }}</td>
      <td>{{ item.personName }}</td>
      <td><AppTag>{{ item.type }}</AppTag></td>
    </tr>
  </AppTable>
  <div class="detail-section">
    <h3>位置变化演示</h3>
    <p class="note">仅对已启用围栏及其适用人员生成记录。</p>
    <form class="form-stack" @submit.prevent="submit">
      <AppField label="人员">
        <AppSelect v-model="personId" name="personId" :options="roster" />
      </AppField>
      <AppField label="目标位置">
        <AppSelect v-model="target" name="target" :options="targets" />
      </AppField>
      <AppButton type="submit" tone="primary">模拟位置变化</AppButton>
      <p class="form-error" role="alert">{{ error }}</p>
    </form>
  </div>
</template>
