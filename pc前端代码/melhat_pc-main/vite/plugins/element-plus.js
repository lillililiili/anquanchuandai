import Components from 'unplugin-vue-components/vite'
import { ElementPlusResolver } from 'unplugin-vue-components/resolvers'
import ElementPlus from 'unplugin-element-plus/vite'

export default function createElementPlus() {
  return [
    // 自动导入 Element Plus 组件
    Components({
      dirs: [], // 明确设置为空数组，避免 undefined
      resolvers: [
        ElementPlusResolver({
          importStyle: 'sass' // 使用 sass 样式，更好的定制性
        })
      ],
      dts: false // 不生成类型声明文件
    }),
    // 自动导入 Element Plus 样式
    ElementPlus({
      useSource: true
    })
  ]
}