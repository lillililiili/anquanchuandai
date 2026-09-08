import { createSvgIconsPlugin } from 'vite-plugin-svg-icons'
import path from 'path'
import { fileURLToPath } from 'url'

// 将 import.meta.url 转换为当前文件的路径
const __filename = fileURLToPath(import.meta.url)
// 然后使用 path.dirname 获取目录路径
const __dirname = path.dirname(__filename)

export default function createSvgIcon(isBuild) {
  return createSvgIconsPlugin({
    // 使用转换后的 __dirname 来解析目录路径
    iconDirs: [path.resolve(__dirname, 'src/assets/icons/svg')],
    symbolId: 'icon-[dir]-[name]',
    svgoOptions: isBuild,
  })
}
