import { createApp } from 'vue'
import { createPinia } from 'pinia'
import { router } from './router'
import App from './App.vue'
import './styles.css'
import RowMore from './components/RowMore.vue'
import { tablePresentation } from './tablePresentation'

createApp(App).component('RowMore', RowMore).directive('table', tablePresentation).use(createPinia()).use(router).mount('#app')
