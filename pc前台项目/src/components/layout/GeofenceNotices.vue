<script setup>
import { onUnmounted, ref, watch } from 'vue';
import { useRouter } from 'vue-router';
import GeofenceNoticePanel from './GeofenceNoticePanel.vue';
import { db, tick, connection } from '@/mock/runtime';
import { session } from '@/stores/session';
import { closeModal } from '@/stores/modal';
import { onAuthCleared } from '@/lib/auth';
import { createGeofenceNoticeTracker } from '@/lib/geofence-notices';

const router = useRouter();
const tracker = createGeofenceNoticeTracker();
const notices = ref([]);
watch(() => [tick.value, session.station, connection.value.status], () => {
  notices.value = tracker.update({ accountId: db.state.operator?.id, station: session.station,
    online: connection.value.status === 'online', events: db.state.events });
}, { immediate: true });
const stopAuth = onAuthCleared(() => { tracker.reset(); notices.value = []; });
onUnmounted(stopAuth);

function open(item) {
  notices.value = tracker.dismiss(item.id);
  closeModal();
  router.push('/event/' + encodeURIComponent(item.id));
}
function openAll() {
  session.filters.alarms = { type: '电子围栏' };
  closeModal();
  router.push('/alarms');
}
</script>

<template>
  <GeofenceNoticePanel :notices="notices" @open="open" @open-all="openAll"
    @dismiss="notices = tracker.dismiss($event)" @dismiss-all="notices = tracker.dismissAll()" />
</template>
