import vue from '@vitejs/plugin-vue'

import createAutoImport from './auto-import'
import createSvgIcon from './svg-icon'
import createCompression from './compression'
import createSetupExtend from './setup-extend'
import createElementPlus from './element-plus'
export default function createVitePlugins(viteEnv, isBuild = false) {
  const vitePlugins = [vue()]
  vitePlugins.push(createAutoImport())
  vitePlugins.push(createSetupExtend())
  vitePlugins.push(createSvgIcon(isBuild))
  // Element Plus 按需导入
  vitePlugins.push(...createElementPlus())
  isBuild && vitePlugins.push(...createCompression(viteEnv))
  return vitePlugins
}
