<script setup>
import { computed } from "vue";
import AppEmpty from "@/components/ui/AppEmpty.vue";
import AppTag from "@/components/ui/AppTag.vue";
import { db, tick } from "@/mock/runtime";
import { personName } from "@/lib/queries";

const props = defineProps({
  workId: { type: String, default: "" },
  work: { type: Object, default: null },
});

const record = computed(() => {
  tick.value;
  return props.work || (props.workId ? db.work(props.workId) : null);
});
</script>

<template>
  <AppEmpty v-if="!record" text="暂无关联作业" />
  <dl v-else class="info">
    <dt>工作票号</dt>
    <dd>{{ record.id }} <AppTag color="muted">只读</AppTag></dd>
    <dt>作业名称</dt>
    <dd>{{ record.name }}</dd>
    <dt>作业区域</dt>
    <dd>{{ record.area }}</dd>
    <dt>监护人</dt>
    <dd>{{ personName(record.supervisor) }}</dd>
    <dt>工作负责人</dt>
    <dd>{{ personName(record.leader) }}</dd>
    <dt>作业时段</dt>
    <dd>{{ record.date }} {{ record.start }} ～ {{ record.end }}</dd>
    <dt>作业人员</dt>
    <dd>{{ record.members.length }} 人 · {{ record.members.map(personName).join(" / ") }}</dd>
    <dt>作业状态</dt>
    <dd><AppTag>{{ record.status }}</AppTag></dd>
  </dl>
</template>
