<script setup>
import AppButton from "./AppButton.vue";
import { closeModal } from "@/stores/modal";

const props = defineProps({
  onConfirm: { type: Function, default: null },
});

function confirm() {
  const action = props.onConfirm;
  closeModal();
  action?.();
}
</script>

<template>
  <AppButton @click="closeModal">取消</AppButton>
  <AppButton tone="danger" @click="confirm">确认</AppButton>
</template>
