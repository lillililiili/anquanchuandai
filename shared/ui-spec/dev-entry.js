import { createApp } from 'vue'
import { installUiSpec } from './install'
import SpecShowcase from './SpecShowcase.vue'
import './showcase.css'
if(import.meta.env.DEV){const app=createApp(SpecShowcase);installUiSpec(app);app.mount('#app')}
