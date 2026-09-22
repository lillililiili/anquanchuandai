<script setup>
import { computed } from "vue";
import AppTag from "@/components/ui/AppTag.vue";
import { db } from "@/mock/runtime";
import { personName, revision } from "@/lib/queries";

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
    <dd>高处作业、临近热表面、设备能量释放、受限通道</dd>
    <dt>现场措施</dt>
    <dd>按作业方案落实安全隔离、个人防护和监护措施；作业前检查装备与通信状态。</dd>
    <dt>工作负责人</dt>
    <dd>{{ personName(work?.leader) }}</dd>
    <dt>监护人</dt>
    <dd>{{ personName(work?.supervisor) }}</dd>
  </dl>
  <p class="note">本页为来源系统摘要，不在本系统进行作业审批。</p>
</template>
