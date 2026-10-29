<script setup>
import { computed } from "vue";
import AppTag from "@/components/ui/AppTag.vue";
import { db } from "@/mock/runtime";
import { personName, revision } from "@/lib/queries";
import { workRisks } from './work-source';

const props = defineProps({
  workId: { type: String, default: "" },
});

const work = computed(() => {
  revision();
  return db.work(props.workId);
});
</script>

<template>
  <p><AppTag color="yellow">来源摘要 · 只读</AppTag></p>
  <dl class="info">
    <dt>工作票编号</dt>
    <dd>{{ workId }}</dd>
    <dt>风险因素</dt>
    <dd>{{ workRisks(work).riskFactors || '尚未取得来源风险信息' }}</dd>
    <dt>现场措施</dt>
    <dd>{{ workRisks(work).measures || '尚未取得来源措施信息' }}</dd>
    <dt>工作负责人</dt>
    <dd>{{ personName(work?.leader) }}</dd>
    <dt>监护人</dt>
    <dd>{{ personName(work?.supervisor) }}</dd>
  </dl>
  <p class="note">本页为来源系统摘要，不在本系统进行作业审批。</p>
</template>
