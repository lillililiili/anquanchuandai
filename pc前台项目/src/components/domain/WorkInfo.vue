<script setup>
import { workBusinessEnabled, workSource, workStatus, workPeriodText } from '@/lib/work-business';
import { computed } from "vue";
import AppEmpty from "@/components/ui/AppEmpty.vue";
import AppTag from "@/components/ui/AppTag.vue";
import { db, tick } from "@/mock/runtime";
import { personName } from "@/lib/queries";
import { externalStatusPresentation, hasExternalSource } from '@/lib/external-status';

const workEnabled = computed(() => { tick.value; return workBusinessEnabled(db); });
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
  <template v-if="workEnabled">
  <AppEmpty v-if="!record" text="暂无关联作业" />
  <dl v-else class="info">
    <dt>数据来源</dt>
    <dd>{{ workSource(record) }}<template v-if="hasExternalSource(record)"> · {{ externalStatusPresentation(record).label }}</template></dd>
    <dt>作业编号</dt>
    <dd>{{ record.id }} <AppTag color="muted">只读</AppTag></dd>
    <dt>作业名称</dt>
    <dd>{{ record.name }}</dd>
    <dt>作业地点</dt>
    <dd>{{ record.area }}</dd>
    <dt>监护人</dt>
    <dd>{{ personName(record.supervisor) }}</dd>
    <dt>工作负责人</dt>
    <dd>{{ personName(record.leader) }}</dd>
    <dt>作业时段</dt>
    <dd>{{ workPeriodText(record) }}</dd>
    <dt>作业人员</dt>
    <dd>{{ record.members.length }} 人 · {{ record.members.map(personName).join(" / ") }}</dd>
    <dt>作业状态</dt>
    <dd><AppTag>{{ workStatus(record) }}</AppTag></dd>
  </dl>
  </template>
</template>
