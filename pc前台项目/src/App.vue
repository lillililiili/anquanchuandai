<script setup>
import { computed, onUnmounted, watchEffect } from "vue";
import { pageFamily } from "@/components/layout/navigation";
import { useRoute, useRouter } from "vue-router";
import AppIcon from "@/components/ui/AppIcon.vue";
import AppModal from "@/components/ui/AppModal.vue";
import AppShell from "@/components/layout/AppShell.vue";
import { modal, modalFooter, modalProps, modalView } from "@/stores/modal";
import { toasts } from "@/stores/notify";
import { db, tick, connection, refreshSnapshot } from "@/mock/runtime";

import { clearWorkSelection, withoutWorkQuery } from '@/lib/work-business';
import { session } from '@/stores/session';
const route = useRoute(), router = useRouter();
watchEffect(() => {
  tick.value;
  if (db.state.businessConfig?.workBusinessEnabled !== false) return;
  clearWorkSelection(session);
  if (['works', 'work'].includes(route.name)) router.replace({ name: 'overview' });
  else {
    const query = withoutWorkQuery(route.query);
    if (Object.keys(query).length !== Object.keys(route.query).length) router.replace({ path: route.path, query });
  }
});
const bare = computed(() => route.name === "login" || route.name === "screen");
watchEffect(() => {
  if (!route.name || route.name === 'login') {
    delete document.documentElement.dataset.portalTheme;
    delete document.documentElement.dataset.portalFamily;
  } else {
    document.documentElement.dataset.portalTheme = route.name === 'screen' ? 'screen' : 'business';
    document.documentElement.dataset.portalFamily = pageFamily(route.name);
  }
});
onUnmounted(() => {
  delete document.documentElement.dataset.portalTheme;
  delete document.documentElement.dataset.portalFamily;
});
</script>

<template>
  <div v-if="route.name !== 'login' && connection.status !== 'online'" role="alert" class="connection-notice">
    {{ connection.message }} <button type="button" @click="refreshSnapshot">重新连接</button>
  </div>
  <RouterView v-if="bare" />
  <AppShell v-else>
    <RouterView />
  </AppShell>
  <AppModal v-if="modal.open" :title="modal.title" :wide="modal.wide" :size="modal.size" :layout="modal.layout" :tone="modal.tone">
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
.connection-notice { position: fixed; top: 0; left: 0; right: 0; z-index: 10000; padding: 10px 16px; color: var(--theme-heading); background: var(--theme-red); text-align: center; }
.connection-notice button { margin-left: 12px; color: inherit; background: transparent; border: 1px solid currentColor; padding: 4px 10px; cursor: pointer; }
</style>
