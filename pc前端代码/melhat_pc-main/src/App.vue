<template>
  <el-config-provider :locale="locale" :size="size">
    <router-view />
  </el-config-provider>
</template>

<script setup>
import Cookies from 'js-cookie'
import zhCn from 'element-plus/es/locale/lang/zh-cn'
import { ref } from 'vue'
import useSettingsStore from '@/store/modules/settings'
import { applyColorMode, handleThemeStyle } from '@/utils/theme'

// Element Plus 全局配置
const locale = ref(zhCn)
const size = computed(() => Cookies.get('size') || 'default')
const settingsStore = useSettingsStore()

applyColorMode('light')

onMounted(() => {
  nextTick(() => {
    handleThemeStyle(settingsStore.theme)
  })
})
</script>
