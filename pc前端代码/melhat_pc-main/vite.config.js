import { defineConfig, loadEnv } from 'vite'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

import createVitePlugins from './vite/plugins/index.js'

const __dirname = path.dirname(fileURLToPath(import.meta.url))

export default defineConfig(({ mode, command }) => {
  const env = loadEnv(mode, process.cwd())

  return {
    // Keep Vite's generated dependency cache outside node_modules. On some
    // Windows development machines node_modules is read-only/locked, which
    // makes lazy-loaded routes stall while Vite repeatedly retries optimizeDeps.
    cacheDir: path.resolve(__dirname, '.vite-cache'),
    plugins: createVitePlugins(env, command === 'build'),
    resolve: {
      extensions: ['.mjs', '.js', '.ts', '.jsx', '.tsx', '.json', '.vue'],
      alias: {
        '@': path.resolve(__dirname, 'src')
      }
    },
    server: {
      host: '0.0.0.0',
      port: 5175,
      // Transform the formal admin pages while the dev server is idle so the
      // first menu click does not have to compile a large Vue view on demand.
      warmup: {
        clientFiles: [
          './src/views/dashboard/index.vue',
          './src/views/people/index.vue',
          './src/views/organization/index.vue',
          './src/views/spaces/index.vue',
          './src/views/devices/index.vue',
          './src/views/product-models/index.vue',
          './src/views/assignments/index.vue',
          './src/views/work-tasks/index.vue',
          './src/views/geo-fences/index.vue',
          './src/views/audit/events/index.vue',
          './src/views/audit/files/index.vue'
        ]
      },
      proxy: {
        '/dev-api': {
          target: process.env.VITE_PROXY_TARGET || 'http://127.0.0.1:18084',
          changeOrigin: true,
          rewrite: (requestPath) => requestPath.replace(/^\/dev-api/, '')
        }
      }
    },
    preview: {
      host: '0.0.0.0',
      port: Number(process.env.VITE_DEV_PORT || 5175),
      proxy: {
        '/dev-api': {
          target: process.env.VITE_PROXY_TARGET || 'http://127.0.0.1:18084',
          changeOrigin: true,
          rewrite: (requestPath) => requestPath.replace(/^\/dev-api/, '')
        }
      }
    }
  }
})
