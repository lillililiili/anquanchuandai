// Standalone development entry. Not part of the production index.html graph.
import { createApp } from 'vue'
import { installUiSpec } from '@ui-spec/install'
import AdminShowcase from './components/AdminShowcase.vue'
import AdminPagination from './components/AdminPagination.vue'
import './styles.css'
import '@ui-spec/tokens.css'
import './styles/spec-adapter.css'
import '@ui-spec/controls.css'
import '@ui-spec/icon-masks.css'
import './styles/admin-shell.css'
import './styles/admin-business.css'
if (import.meta.env.DEV) {
  document.documentElement.dataset.adminTheme='business'
  document.documentElement.dataset.adminFamily='list'
  const app=createApp(AdminShowcase)
  installUiSpec(app)
  app.component('AdminPagination',AdminPagination).mount('#app')
}

import '@ui-spec/dialog.css';
