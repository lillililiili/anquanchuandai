import { defineConfig } from 'vitest/config'
import vue from '@vitejs/plugin-vue'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import setupExtend from 'vite-plugin-vue-setup-extend'
import autoImport from 'unplugin-auto-import/vite'

const __dirname = path.dirname(fileURLToPath(import.meta.url))

export default defineConfig({
  plugins: [
    vue(),
    setupExtend(),
    autoImport({
      imports: [
        'vue',
        'vue-router',
        'pinia'
      ],
      dts: false
    })
  ],
  resolve: {
    alias: {
      '~': path.resolve(__dirname, './'),
      '@': path.resolve(__dirname, './src')
    },
    extensions: ['.mjs', '.js', '.ts', '.jsx', '.tsx', '.json', '.vue']
  },
  test: {
    globals: true,
    environment: 'jsdom',
    env: {
      VITE_APP_TITLE: '智能穿戴管理平台'
    },
    setupFiles: ['./src/__tests__/setup.ts'],
    include: ['src/**/*.{test,spec}.{js,ts,jsx,tsx}'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
      include: ['src/**/*.{js,ts,vue}'],
      exclude: [
        'src/main.ts',
        'src/permission.ts',
        'src/utils/request.ts',
        'src/api/**',
        'src/assets/**',
        'src/icons/**'
      ]
    },
    // server: process.env.VITEST ? {
    //   deps: {
    //     optimizer: {
    //       web: {
    //         include: ['element-plus']
    //       }
    //     }
    //   }
    // } : undefined
  },
})
