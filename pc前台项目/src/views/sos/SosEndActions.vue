<script setup>
import AppButton from "@/components/ui/AppButton.vue";
import { db } from "@/mock/runtime";
import { closeModal } from "@/stores/modal";
import { toast } from "@/stores/notify";

defineOptions({ inheritAttrs: false });
const props = defineProps({ eventId: { type: String, required: true } });
let busy = false;

async function confirmEnd() {
  if (busy) return; busy = true;
  try {
    await db.sos("end", props.eventId);
    closeModal();
    toast("SOS 协助已结束，记录已保存");
  } catch (error) {
    toast(error.message || "操作失败", true);
  } finally { busy = false; }
}
</script>

<template>
  <AppButton @click="closeModal">取消</AppButton>
  <AppButton tone="danger" @click="confirmEnd">确认</AppButton>
</template>
