import { createApp } from 'vue';
import { installUiSpec } from '@ui-spec/install';
import PaginationFixture from './PaginationFixture.vue';
import '../../src/styles/index.css';
import '@ui-spec/tokens.css';
import '../../src/styles/spec-theme.css';
import '../../src/styles/spec-adapter.css';
import '@ui-spec/controls.css';
import '@ui-spec/icon-masks.css';
import '../../src/styles/portal-business.css';

// Isolated local records; never reads or writes business data. Not a production entry.
if (import.meta.env.DEV) {
  document.documentElement.dataset.portalTheme='business';
  document.documentElement.dataset.portalFamily='list';
  const app=createApp(PaginationFixture); installUiSpec(app); app.mount('#app');
}
