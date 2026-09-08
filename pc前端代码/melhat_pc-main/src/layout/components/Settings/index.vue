<template>
  <el-drawer
    v-model="showSettings"
    direction="rtl"
    size="300px"
    :withHeader="false"
  >
    <div class="setting-drawer-title">
      <h3 class="drawer-title">主题风格设置</h3>
    </div>

    <div class="setting-drawer-block-checbox">
      <div class="setting-drawer-block-checbox-item" @click="handleTheme('theme-dark')">
        <img src="@/assets/images/dark.svg" alt="dark" />
        <div v-if="sideTheme === 'theme-dark'" class="setting-drawer-block-checbox-selectIcon">
          <check />
        </div>
      </div>
      <div class="setting-drawer-block-checbox-item" @click="handleTheme('theme-light')">
        <img src="@/assets/images/light.svg" alt="light" />
        <div v-if="sideTheme === 'theme-light'" class="setting-drawer-block-checbox-selectIcon">
          <check />
        </div>
      </div>
    </div>

    <div class="drawer-item">
      <span>主题颜色</span>
      <span class="comp-style">
        <el-color-picker
          v-model="theme"
          :predefine="predefineColors"
          @change="themeChange"
        />
      </span>
    </div>
    <el-divider />

    <h3 class="drawer-title">系统布局配置</h3>

    <div class="drawer-item">
      <span>开启 TopNav</span>
      <span class="comp-style">
        <el-switch v-model="topNav" class="drawer-switch" />
      </span>
    </div>

    <div class="drawer-item">
      <span>开启 Tags-Views</span>
      <span class="comp-style">
        <el-switch v-model="tagsView" class="drawer-switch" />
      </span>
    </div>

    <div class="drawer-item">
      <span>固定 Header</span>
      <span class="comp-style">
        <el-switch v-model="fixedHeader" class="drawer-switch" />
      </span>
    </div>

    <div class="drawer-item">
      <span>显示 Logo</span>
      <span class="comp-style">
        <el-switch v-model="sidebarLogo" class="drawer-switch" />
      </span>
    </div>

    <div class="drawer-item">
      <span>动态标题</span>
      <span class="comp-style">
        <el-switch v-model="dynamicTitle" class="drawer-switch" />
      </span>
    </div>

    <el-divider />

    <el-button icon="DocumentAdd" plain type="primary" @click="saveSetting"
      >保存配置</el-button
    >
    <el-button icon="Refresh" plain @click="resetSetting">重置配置</el-button>
  </el-drawer>
</template>

<script setup>
import axios from 'axios'
import { ElLoading, ElMessage } from 'element-plus'
import { useDynamicTitle } from '@/utils/dynamicTitle'
import useAppStore from '@/store/modules/app'
import useSettingsStore from '@/store/modules/settings'
import usePermissionStore from '@/store/modules/permission'
import { handleThemeStyle } from '@/utils/theme'

const { proxy } = getCurrentInstance()
const appStore = useAppStore()
const settingsStore = useSettingsStore()
const permissionStore = usePermissionStore()
const showSettings = ref(false)
const theme = ref(settingsStore.theme)
const sideTheme = ref(settingsStore.sideTheme)
const storeSettings = computed(() => settingsStore)
// 科技蓝主题预设色 - 工业场景专业感
const predefineColors = ref([
  '#4f8ff7',
  '#3d7ee8',
  '#2f6fd6',
  '#5d9cec',
  '#3976c8',
  '#426b9d',
])

/** 是否需要topnav */
const topNav = computed({
  get: () => storeSettings.value.topNav,
  set: val => {
    settingsStore.changeSetting({ key: 'topNav', value: val })
    if (!val) {
      appStore.toggleSideBarHide(false)
      permissionStore.setSidebarRouters(permissionStore.defaultRoutes)
    }
  }
})
/** 是否需要tagview */
const tagsView = computed({
  get: () => storeSettings.value.tagsView,
  set: val => {
    settingsStore.changeSetting({ key: 'tagsView', value: val })
  }
})
/**是否需要固定头部 */
const fixedHeader = computed({
  get: () => storeSettings.value.fixedHeader,
  set: val => {
    settingsStore.changeSetting({ key: 'fixedHeader', value: val })
  }
})
/**是否需要侧边栏的logo */
const sidebarLogo = computed({
  get: () => storeSettings.value.sidebarLogo,
  set: val => {
    settingsStore.changeSetting({ key: 'sidebarLogo', value: val })
  }
})
/**是否需要侧边栏的动态网页的title */
const dynamicTitle = computed({
  get: () => storeSettings.value.dynamicTitle,
  set: val => {
    settingsStore.changeSetting({ key: 'dynamicTitle', value: val })
    // 动态设置网页标题
    useDynamicTitle()
  }
})

function themeChange(val) {
  settingsStore.changeSetting({ key: 'theme', value: val })
  theme.value = val
  handleThemeStyle(val)
}
function handleTheme(val) {
  settingsStore.changeSetting({ key: 'sideTheme', value: val })
  sideTheme.value = val
}
function saveSetting() {
  proxy.$modal.loading('正在保存到本地，请稍候...')
  let layoutSetting = {
    topNav: storeSettings.value.topNav,
    tagsView: storeSettings.value.tagsView,
    fixedHeader: storeSettings.value.fixedHeader,
    sidebarLogo: storeSettings.value.sidebarLogo,
    dynamicTitle: storeSettings.value.dynamicTitle,
    sideTheme: storeSettings.value.sideTheme,
    theme: storeSettings.value.theme,
    colorMode: storeSettings.value.colorMode
  }
  localStorage.setItem('layout-setting', JSON.stringify(layoutSetting))
  setTimeout(proxy.$modal.closeLoading(), 1000)
}
function resetSetting() {
  proxy.$modal.loading('正在清除设置缓存并刷新，请稍候...')
  localStorage.removeItem('layout-setting')
  localStorage.removeItem('color-mode')
  setTimeout('window.location.reload()', 1000)
}
function openSetting() {
  showSettings.value = true
}

defineExpose({
  openSetting
})
</script>

<style lang="scss" scoped>
@use '@/assets/styles/variables.module.scss' as *;

.setting-drawer-title {
  margin-bottom: 12px;
  color: $text-primary;
  line-height: 22px;
  font-weight: 600;
  .drawer-title {
    font-size: 14px;
  }
}
.setting-drawer-block-checbox {
  display: flex;
  justify-content: flex-start;
  align-items: center;
  margin-top: 10px;
  margin-bottom: 20px;

  .setting-drawer-block-checbox-item {
    position: relative;
    margin-right: 16px;
    border-radius: $radius;
    cursor: pointer;
    border: 1px solid $border;

    img {
      width: 48px;
      height: 48px;
      border-radius: $radius-sm;
    }

    .custom-img {
      width: 48px;
      height: 38px;
      border-radius: $radius-sm;
      box-shadow: 1px 1px 2px $border;
    }

    .setting-drawer-block-checbox-selectIcon {
      position: absolute;
      top: 0;
      right: 0;
      width: 100%;
      height: 100%;
      padding-top: 15px;
      padding-left: 24px;
      color: $brand-primary;
      font-weight: 700;
      font-size: 14px;
    }
  }
}

.drawer-item {
  color: $text-secondary;
  padding: 12px 0;
  font-size: 14px;

  .comp-style {
    float: right;
    margin: -3px 8px 0px 0px;
  }
}
</style>
