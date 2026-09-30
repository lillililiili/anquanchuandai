<script setup>
import AppButton from "@/components/ui/AppButton.vue";
import { closeModal } from "@/stores/modal";
import { go } from "@/lib/actions";
import { authFetch, clearAuth } from "@/lib/auth";

async function logout() {
  try { await authFetch("/api/guardian/v1/logout", { method: "POST" }); } catch { /* local logout still clears the session */ }
  clearAuth();
  closeModal();
  go("login");
}
</script>

<template>
  <AppButton tone="danger" @click="logout">退出登录</AppButton>
</template>
