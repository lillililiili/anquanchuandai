import { defineConfig, loadEnv } from 'vite'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

import createVitePlugins from './vite/plugins/index.js'
import { adminMockHtml } from './vite/admin-mock.js'

const __dirname = path.dirname(fileURLToPath(import.meta.url))

export default defineConfig(({ mode, command }) => {
  const env = loadEnv(mode, process.cwd())
  const mock = mode === 'admin-mock'

  return {
    plugins: [...createVitePlugins(env, command === 'build'), ...(mock ? [adminMockHtml()] : [])],
    ...(mock ? {
      publicDir: false,
      build: { outDir: 'dist-admin-mock' },
      preview: { host: '127.0.0.1', port: 5182, strictPort: true }
    } : {}),
    resolve: {
      extensions: ['.mjs', '.js', '.ts', '.jsx', '.tsx', '.json', '.vue'],
      alias: {
        '@': path.resolve(__dirname, 'src'),
        '@admin-provider': path.resolve(__dirname, mock ? 'src/admin-mock/provider.js' : 'src/admin-provider-disabled.js')
      }
    },
    server: mock ? { host: '127.0.0.1', port: 5181, strictPort: true, proxy: {} } : {
      host: '0.0.0.0',
      port: 5175,
      proxy: {
        '/dev-api': {
          target: env.VITE_APP_PROXY_TARGET || 'http://127.0.0.1:18084',
          changeOrigin: true,
          rewrite: (requestPath) => requestPath.replace(/^\/dev-api/, '')
        }
      }
    }
  }
})
