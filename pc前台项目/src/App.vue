<script setup>
import { computed } from "vue";
import { useRoute } from "vue-router";
import AppIcon from "@/components/ui/AppIcon.vue";
import AppModal from "@/components/ui/AppModal.vue";
import AppShell from "@/components/layout/AppShell.vue";
import { modal, modalFooter, modalProps, modalView } from "@/stores/modal";
import { toasts } from "@/stores/notify";
import { connection, refreshSnapshot } from "@/mock/runtime";

const route = useRoute();
const bare = computed(() => route.name === "login" || route.name === "screen");
</script>

<template>
  <div v-if="route.name !== 'login' && connection.status !== 'online'" role="alert" class="connection-notice">
    {{ connection.message }} <button type="button" @click="refreshSnapshot">重新连接</button>
  </div>
  <RouterView v-if="bare" />
  <AppShell v-else>
    <RouterView />
  </AppShell>
  <AppModal v-if="modal.open" :title="modal.title" :wide="modal.wide" :tone="modal.tone">
    <component :is="modalView" v-bind="modalProps" />
    <template v-if="modalFooter" #footer>
      <component :is="modalFooter" v-bind="modalProps" />
    </template>
  </AppModal>
  <div id="toasts" role="status" aria-live="polite">
    <div v-for="item in toasts" :key="item.id" :class="['toast', item.error ? 'error' : '']">
      <AppIcon :name="item.error ? 'error-warning-line' : 'checkbox-circle-line'" />
      {{ item.text }}
    </div>
  </div>
</template>

<style scoped>
.connection-notice { position: fixed; top: 0; left: 0; right: 0; z-index: 10000; padding: 10px 16px; color: #fff; background: #8a3a09; text-align: center; }
.connection-notice button { margin-left: 12px; color: inherit; background: transparent; border: 1px solid currentColor; padding: 4px 10px; cursor: pointer; }
</style>
