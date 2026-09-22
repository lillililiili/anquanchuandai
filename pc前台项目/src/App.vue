<script setup>
import { computed } from "vue";
import { useRoute } from "vue-router";
import AppIcon from "@/components/ui/AppIcon.vue";
import AppModal from "@/components/ui/AppModal.vue";
import AppShell from "@/components/layout/AppShell.vue";
import { modal, modalFooter, modalProps, modalView } from "@/stores/modal";
import { toasts } from "@/stores/notify";

const route = useRoute();
const bare = computed(() => route.name === "login");
</script>

<template>
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
