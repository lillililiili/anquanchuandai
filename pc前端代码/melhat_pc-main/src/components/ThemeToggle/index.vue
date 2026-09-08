<template>
  <el-dropdown
    class="right-menu-item hover-effect theme-toggle-container"
    trigger="click"
    @command="handleTheme"
  >
    <button class="theme-icon-wrapper" type="button" aria-label="切换界面主题">
      <el-icon :size="18"><component :is="currentIcon" /></el-icon>
    </button>
    <template #dropdown>
      <el-dropdown-menu>
        <el-dropdown-item command="dark" :class="{ 'is-active': colorMode === 'dark' }">
          <el-icon><Moon /></el-icon>
          <span>深色模式</span>
        </el-dropdown-item>
        <el-dropdown-item command="light" :class="{ 'is-active': colorMode === 'light' }">
          <el-icon><Sunny /></el-icon>
          <span>浅色模式</span>
        </el-dropdown-item>
        <el-dropdown-item command="auto" :class="{ 'is-active': colorMode === 'auto' }">
          <el-icon><Monitor /></el-icon>
          <span>跟随系统</span>
        </el-dropdown-item>
      </el-dropdown-menu>
    </template>
  </el-dropdown>
</template>

<script setup>
import { computed } from 'vue'
import { Monitor, Moon, Sunny } from '@element-plus/icons-vue'
import useSettingsStore from '@/store/modules/settings'

const settingsStore = useSettingsStore()
const colorMode = computed(() => settingsStore.colorMode)

const currentIcon = computed(() => {
  if (colorMode.value === 'light') return Sunny
  if (colorMode.value === 'auto') return Monitor
  return Moon
})

function handleTheme(mode) {
  settingsStore.setColorMode(mode)
}
</script>

<style lang="scss" scoped>
.theme-icon-wrapper {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 36px;
  height: 36px;
  padding: 0;
  color: var(--text-secondary);
  border: 0;
  border-radius: 8px;
  background: transparent;
  cursor: pointer;

  &:hover {
    color: var(--text-primary);
    background: var(--bg-hover);
  }
}

:global(.el-dropdown-menu__item.is-active) {
  color: var(--color-primary);
  background: var(--color-primary-soft);
  font-weight: 600;
}
</style>
