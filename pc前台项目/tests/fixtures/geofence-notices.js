import { createApp } from 'vue';
import GeofenceNoticeFixture from './GeofenceNoticeFixture.vue';
import '@ui-spec/tokens.css';
import '@ui-spec/controls.css';
import '@ui-spec/icon-masks.css';
if (import.meta.env.DEV) createApp(GeofenceNoticeFixture).mount('#app');
