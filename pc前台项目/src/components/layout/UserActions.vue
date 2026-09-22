<script setup>
import AppButton from "@/components/ui/AppButton.vue";
import { closeModal } from "@/stores/modal";
import { go } from "@/lib/actions";

function logout() {
  sessionStorage.removeItem("rolling-session");
  closeModal();
  go("login");
}
</script>

<template>
  <AppButton tone="danger" @click="logout">退出登录</AppButton>
</template>
