import { fileURLToPath, URL } from 'node:url'
import { defineConfig, loadEnv } from 'vite'
import vue from '@vitejs/plugin-vue'
import Components from 'unplugin-vue-components/vite'
import { ElementPlusResolver } from 'unplugin-vue-components/resolvers'

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  const demo = mode === 'demo'
  const mock = mode === 'mock'
  const apiPrefix = demo ? '/demo-api' : '/dev-api'
  return {
    base: env.VITE_BASE_PATH || '/',
    plugins: [vue(), Components({
      dirs: [], dts: false,
      resolvers: [ElementPlusResolver({ importStyle: 'sass' })]
    })],
    define: { __PORTAL_DEMO__: JSON.stringify(demo) },
    build: { outDir: mock ? 'dist-mock' : demo ? 'dist-demo' : 'dist' },
    resolve: { alias: {
      '@statistics-view': fileURLToPath(new URL(mock ? './src/mock/StatisticsView.vue' : './src/views/statistics/StatisticsUnavailable.vue', import.meta.url)),
      '@dispatch-runtime': fileURLToPath(new URL(mock ? './src/mock/dispatch-runtime.js' : './src/api/dispatch-unavailable.js', import.meta.url)),
      '@dispatch-view': fileURLToPath(new URL(mock ? './src/mock/DispatchView.vue' : './src/views/dispatch/DispatchUnavailable.vue', import.meta.url)),
      '@dispatch-banner': fileURLToPath(new URL(mock ? './src/mock/DispatchBanner.vue' : './src/components/ClosedExtension.js', import.meta.url)),
      '@contact-entry': fileURLToPath(new URL(mock ? './src/mock/ContactEntry.vue' : './src/components/ClosedExtension.js', import.meta.url)),
      '@work-view': fileURLToPath(new URL(mock ? './src/mock/WorkView.vue' : './src/views/supervision/SupervisionUnavailable.vue', import.meta.url)),
      '@event-actions': fileURLToPath(new URL(mock ? './src/mock/EventActions.vue' : './src/components/ClosedExtension.js', import.meta.url)),
      '@portal-video-player': fileURLToPath(new URL(mock ? './src/mock/MockVideoPlayer.vue' : './src/components/video/VideoPlayer.vue', import.meta.url)),
      '@spatial-actions': fileURLToPath(new URL(mock ? './src/mock/spatial-provider.js' : './src/api/spatial-unavailable.js', import.meta.url)),
      '@fence-editor': fileURLToPath(new URL(mock ? './src/mock/FenceEditor.vue' : './src/components/ClosedExtension.js', import.meta.url)),
      '@material-actions': fileURLToPath(new URL(mock ? './src/mock/MaterialActions.vue' : './src/components/ClosedExtension.js', import.meta.url)),
      '@vitals-provider': fileURLToPath(new URL(mock ? './src/mock/vitals-provider.js' : './src/api/vitals-unavailable.js', import.meta.url)),
      '@equipment-provider': fileURLToPath(new URL(mock ? './src/mock/equipment-provider.js' : './src/api/equipment-unavailable.js', import.meta.url)),
      '@mock-assignment': fileURLToPath(new URL(mock ? './src/mock/AssignmentDialog.vue' : './src/components/ClosedExtension.js', import.meta.url)),
      '@workbench-provider': fileURLToPath(new URL(mock ? './src/mock/workbench-provider.js' : './src/api/workbench-unavailable.js', import.meta.url)),
      '@/utils/request': fileURLToPath(new URL(mock ? './src/mock/request.js' : './src/utils/request.js', import.meta.url)),
      '@mock-controls': fileURLToPath(new URL(mock ? './src/mock/MockControls.vue' : './src/components/ClosedExtension.js', import.meta.url)),
      '@': fileURLToPath(new URL('./src', import.meta.url)), '@demo-assignment': fileURLToPath(new URL(demo ? './src/demo/AssignmentActions.vue' : './src/components/ClosedExtension.js', import.meta.url)) } },
    server: {
      host: '127.0.0.1', port: mock ? 5179 : demo ? 5178 : 5176, strictPort: true,
      proxy: mock ? {} : { [apiPrefix]: {
        target: env.VITE_API_PROXY_TARGET || 'http://127.0.0.1:18084',
        changeOrigin: true,
        rewrite: (path) => path.slice(apiPrefix.length)
      } }
    },
    preview: { host: '127.0.0.1' }
  }
})
