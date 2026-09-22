<script setup>
import { computed } from "vue";
import AppButton from "@/components/ui/AppButton.vue";
import AppTable from "@/components/ui/AppTable.vue";
import AppTag from "@/components/ui/AppTag.vue";
import { events, personName, revision } from "@/lib/queries";
import { closeModal } from "@/stores/modal";
import { go } from "@/lib/actions";

function urgency(item) {
  if (item.type === "人员求助" && item.status !== "已核验") return 0;
  if (item.status === "待认领") return 1;
  if (item.status === "待现场核验") return 2;
  if (item.status === "处理中") return 3;
  return 4;
}

const rows = computed(() => {
  revision();
  return events()
    .filter((item) => item.status !== "已核验")
    .sort((a, b) => urgency(a) - urgency(b) || b.time.localeCompare(a.time));
});

const openSos = computed(() => rows.value.filter((item) => item.type === "人员求助"));
const leadSos = computed(() => openSos.value[0] || null);

function open(id) {
  closeModal();
  go("event/" + id);
}
</script>

<template>
  <a v-if="leadSos" class="sos-call notice-sos" :href="'#/event/' + leadSos.id" @click="closeModal">
    <span class="sos-call-mark">SOS</span>
    <span class="sos-call-copy">
      <strong>{{ leadSos.snapshot?.personName || personName(leadSos.personId) }} 正在求助</strong>
      <small>{{ leadSos.title }} · {{ leadSos.deviceId }} · {{ leadSos.time }}</small>
    </span>
    <span class="sos-call-go">立即响应</span>
  </a>
  <AppTable :columns="['事件', '人员', '状态', '操作']" :empty="!rows.length">
    <tr v-for="item in rows" :key="item.id" :class="item.type === '人员求助' ? 'is-sos' : ''">
      <td>
        <AppTag v-if="item.type === '人员求助'" color="red">SOS</AppTag>
        {{ item.title }}
      </td>
      <td>{{ personName(item.personId) }}</td>
      <td><AppTag :color="item.type === '人员求助' ? 'red' : 'yellow'">{{ item.status }}</AppTag></td>
      <td>
        <AppButton v-if="item.type === '人员求助'" tone="small danger sos-row-go" @click="open(item.id)">立即响应</AppButton>
        <AppButton v-else tone="small" @click="open(item.id)">查看</AppButton>
      </td>
    </tr>
  </AppTable>
</template>
