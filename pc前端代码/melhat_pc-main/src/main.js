import { createApp } from 'vue'


import DictElement from '@/components/DictElement/index.vue'
import '@/assets/styles/index.scss' // global css
import { applyColorMode } from '@/utils/theme'
// Element Plus 样式通过 unplugin-element-plus 按需导入

import BrandLogo from '@/components/BrandLogo/index.vue'
import ModuleHeader from '@/components/ModuleHeader/index.vue'
import BrandedEmpty from '@/components/BrandedEmpty/index.vue'
import App from './App'
import store from './store'
import router from './router'
import directive from './directive' // directive

// 注册指令
import plugins from './plugins' // plugins
import { download } from '@/utils/request'

// svg图标
import 'virtual:svg-icons-register'
import SvgIcon from '@/components/SvgIcon'
import elementIcons from '@/components/SvgIcon/svgicon'


import './permission' // permission control

import { useDict } from '@/utils/dict'
import {
  parseTime,
  resetForm,
  addDateRange,
  handleTree,
  selectDictLabel,
  selectDictLabels
} from '@/utils/ruoyi'

// 分页组件
import Pagination from '@/components/Pagination'
// 自定义表格工具组件
import RightToolbar from '@/components/RightToolbar'
// 富文本组件
import Editor from '@/components/Editor'
// 文件上传组件
import FileUpload from '@/components/FileUpload'
// 图片上传组件
import ImageUpload from '@/components/ImageUpload'
// 图片预览组件
import ImagePreview from '@/components/ImagePreview'
// 自定义树选择组件
import TreeSelect from '@/components/TreeSelect'
// 字典标签组件
import DictTag from '@/components/DictTag'
// 骨架屏组件
import Skeleton from '@/components/Skeleton/index.vue'

// Apply the saved color mode before mounting to avoid a light-theme flash.
applyColorMode('light')
localStorage.setItem('color-mode', 'light')

const app = createApp(App)

// 全局方法挂载
app.config.globalProperties.useDict = useDict
app.config.globalProperties.download = download
app.config.globalProperties.parseTime = parseTime
app.config.globalProperties.resetForm = resetForm
app.config.globalProperties.handleTree = handleTree
app.config.globalProperties.addDateRange = addDateRange
app.config.globalProperties.selectDictLabel = selectDictLabel
app.config.globalProperties.selectDictLabels = selectDictLabels

// 全局组件挂载
app.component('BrandLogo', BrandLogo)
app.component('ModuleHeader', ModuleHeader)
app.component('BrandedEmpty', BrandedEmpty)
app.component('DictTag', DictTag)
app.component('Pagination', Pagination)
app.component('TreeSelect', TreeSelect)
app.component('FileUpload', FileUpload)
app.component('ImageUpload', ImageUpload)
app.component('ImagePreview', ImagePreview)
app.component('RightToolbar', RightToolbar)
app.component('Editor', Editor)
app.component('ele-dict', DictElement)
app.component('skeleton', Skeleton)

app.use(router)
app.use(store)
app.use(plugins)
app.use(elementIcons)
app.component('svg-icon', SvgIcon)

directive(app)

// Element Plus 全局配置已移至 App.vue 的 el-config-provider 组件
// 组件通过 unplugin-vue-components 按需自动导入
// 样式通过 unplugin-element-plus 按需自动导入

app.mount('#app')
