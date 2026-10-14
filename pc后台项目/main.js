import { installUiSpec } from "@ui-spec/install";
import { createApp } from 'vue'
import { createPinia } from 'pinia'
import { router } from './router'
import App from './App.vue'
import './styles.css'
import "@ui-spec/tokens.css";
import "./styles/spec-adapter.css";
import "@ui-spec/controls.css";
import "@ui-spec/icon-masks.css";

import RowMore from './components/RowMore.vue'
import { tablePresentation } from './tablePresentation'

const app = createApp(App)
installUiSpec(app)
app.component('RowMore', RowMore).directive('table', tablePresentation).use(createPinia()).use(router).mount('#app')
