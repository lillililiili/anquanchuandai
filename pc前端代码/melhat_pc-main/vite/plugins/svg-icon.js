import path from 'path'
import { createSvgIconsPlugin } from 'vite-plugin-svg-icons'

export default function createSvgIcon(isBuild) {
    return createSvgIconsPlugin({
		iconDirs: [path.resolve(process.cwd(), 'src/assets/icons/svg')],
        symbolId: 'icon-[dir]-[name]',
        svgoOptions: {
            plugins: [
                {
                    name: 'removeAttrs',
                    params: {
                        attrs: ['fill']  // 移除内联 fill 属性，让 CSS 可以控制颜色
                    }
                }
            ]
        }
    })
}
