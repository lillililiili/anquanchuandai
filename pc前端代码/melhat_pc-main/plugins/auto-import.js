import AutoImport from 'unplugin-auto-import/vite'
import { ElementPlusResolver } from 'unplugin-vue-components/resolvers'
import { VueUseComponentsResolver } from 'unplugin-vue-components/resolvers'

export default function createAutoImport() {
  return AutoImport({
    imports: [
      'vue',
      'vue-router',
      'pinia',
      '@vueuse/core',
      // 可以在这里添加其他需要自动导入的库
    ],
    dts: 'src/auto-imports.d.ts', // 生成自动导入的类型声明文件
    resolvers: [
      ElementPlusResolver(), // 自动导入 Element Plus 组件
      VueUseComponentsResolver(), // 添加 VueUse 组件解析器
    ],
    eslintrc: {
      enabled: true,
    },
  })
}
