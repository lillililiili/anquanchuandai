<script setup>
import { computed } from "vue";
import AppEmpty from "@/components/ui/AppEmpty.vue";
import AppTag from "@/components/ui/AppTag.vue";
import { db } from "@/mock/runtime";
import { personName, revision } from "@/lib/queries";

const props = defineProps({
  callId: { type: String, default: "" },
});

const call = computed(() => {
  revision();
  return db.state.calls.find((item) => item.id === props.callId) || null;
});

const names = computed(() => {
  revision();
  return (call.value?.members || []).map((id) => personName(id)).join("、");
});
</script>

<template>
  <template v-if="call">
    <dl class="info">
      <dt>会话编号</dt>
      <dd>{{ call.id }}</dd>
      <dt>参与人员</dt>
      <dd>{{ names }}</dd>
      <dt>状态</dt>
      <dd><AppTag>{{ call.status }}</AppTag></dd>
    </dl>
    <div class="timeline">
      <div v-for="(item, index) in call.history || []" :key="index" class="timeline-item"><time>{{ item.time }}</time>{{ item.text }}</div>
    </div>
  </template>
  <AppEmpty v-else text="暂无符合条件的记录" />
</template>
