import { createApp } from 'vue'
import { installUiSpec } from '@ui-spec/install'
import ModalFixture from './ModalFixture.vue'
import '../../src/styles/index.css'
import '@ui-spec/tokens.css'
import '../../src/styles/spec-theme.css'
import '../../src/styles/spec-adapter.css'
import '@ui-spec/controls.css'
import '@ui-spec/icon-masks.css'
import '../../src/styles/portal-business.css'
import '@ui-spec/dialog.css'
if (import.meta.env.DEV && location.port === '5193') {
  document.documentElement.dataset.portalTheme = 'business'
  const app = createApp(ModalFixture); installUiSpec(app); app.mount('#app')
}
