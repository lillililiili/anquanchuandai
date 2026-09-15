import Components from 'unplugin-vue-components/vite'
import { ElementPlusResolver } from 'unplugin-vue-components/resolvers'

export default function createElementPlus() {
  return [
    // 自动导入 Element Plus 组件
    Components({
      dirs: [], // 明确设置为空数组，避免 undefined
      resolvers: [
        ElementPlusResolver({
          // The complete customized theme is already loaded once from
          // src/assets/styles/element/index.scss. Per-component style imports
          // duplicated that CSS and made Vite re-optimize dependencies every
          // time a lazy route introduced a new Element Plus component.
          importStyle: false
        })
      ],
      dts: false // 不生成类型声明文件
    })
  ]
}
