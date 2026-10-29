import { createApp } from 'vue';
import { createRouter, createMemoryHistory } from 'vue-router';
import { installUiSpec } from '@ui-spec/install';
import MapLocationFixture from './MapLocationFixture.vue';
import '../../src/styles/index.css';
import '@ui-spec/tokens.css';
import '../../src/styles/spec-theme.css';
import '../../src/styles/spec-adapter.css';
import '@ui-spec/controls.css';
import '@ui-spec/icon-masks.css';
import '../../src/styles/portal-business.css';

// Uses the same fixed test region as the application, without viewer location.
if (import.meta.env.DEV) {
  document.documentElement.dataset.portalTheme = 'business';
  const router = createRouter({ history: createMemoryHistory(), routes: [{ path: '/', name: 'overview', component: MapLocationFixture }] });
  const app = createApp(MapLocationFixture);
  installUiSpec(app);
  app.use(router);
  router.isReady().then(() => app.mount('#app'));
}
