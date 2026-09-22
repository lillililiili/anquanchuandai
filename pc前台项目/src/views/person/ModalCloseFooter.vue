<script setup>
import AppButton from "@/components/ui/AppButton.vue";
import { closeModal } from "@/stores/modal";

defineProps({
  personId: { type: String, default: "" },
});
</script>

<template>
  <AppButton @click="closeModal">关闭</AppButton>
</template>
