import { createApp } from 'vue';
import { installUiSpec } from '@ui-spec/install';
import PortalShowcase from './components/layout/PortalShowcase.vue';
import './styles/index.css';
import '@ui-spec/tokens.css';
import './styles/spec-theme.css';
import './styles/spec-adapter.css';
import '@ui-spec/controls.css';
import '@ui-spec/icon-masks.css';
import './styles/portal-shell.css';
import './styles/portal-business.css';

// Separate Vite HTML entry, excluded from the default production build.
if (import.meta.env.DEV) {
  document.documentElement.dataset.portalTheme = 'business';
  document.documentElement.dataset.portalFamily = 'list';
  const app=createApp(PortalShowcase); installUiSpec(app); app.mount('#app');
}

import '@ui-spec/dialog.css';
