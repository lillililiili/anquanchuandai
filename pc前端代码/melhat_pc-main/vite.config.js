import { defineConfig, loadEnv } from 'vite'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

import createVitePlugins from './vite/plugins/index.js'

const __dirname = path.dirname(fileURLToPath(import.meta.url))

export default defineConfig(({ mode, command }) => {
  const env = loadEnv(mode, process.cwd())

  return {
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
      proxy: {
        '/dev-api': {
          target: 'http://127.0.0.1:18084',
          changeOrigin: true,
          rewrite: (requestPath) => requestPath.replace(/^\/dev-api/, '')
        }
      }
    }
  }
})
