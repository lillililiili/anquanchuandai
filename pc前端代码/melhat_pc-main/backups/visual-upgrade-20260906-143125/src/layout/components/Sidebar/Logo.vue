<template>
  <div class="sidebar-logo-container" :class="{ collapse: collapse }">
    <transition name="sidebarLogoFade">
      <router-link
        v-if="collapse"
        key="collapse"
        class="sidebar-logo-link"
        to="/"
      >
        <img :src="appLogo" alt="分体式智能安全帽平台" class="sidebar-logo-icon" />
      </router-link>
      <router-link v-else key="expand" class="sidebar-logo-link" to="/">
        <div class="logo-wrapper">
          <img :src="appLogo" alt="分体式智能安全帽平台" class="sidebar-logo-icon" />
          <span class="sidebar-title">{{ title }}</span>
        </div>
      </router-link>
    </transition>
  </div>
</template>

<script setup>
import variables from '@/assets/styles/variables.module.scss'
import useSettingsStore from '@/store/modules/settings'
import appLogo from '@/assets/logo/app-logo.png'

defineProps({
  collapse: {
    type: Boolean,
    required: true
  }
})

const title = ref('分体式智能安全帽平台')
const settingsStore = useSettingsStore()
const sideTheme = computed(() => settingsStore.sideTheme)
</script>

<style lang="scss" scoped>
@use '@/assets/styles/variables.module.scss' as *;

.sidebarLogoFade-enter-active {
  transition: opacity 1.5s;
}

.sidebarLogoFade-enter,
.sidebarLogoFade-leave-to {
  opacity: 0;
}

.sidebar-logo-container {
  position: relative;
  width: 100%;
  height: 60px;
  background: var(--sidebar-bg);
  border-bottom: 1px solid var(--sidebar-border);
  text-align: center;
  overflow: hidden;
  padding: 0; // Removed horizontal padding for collapsed centering
  
  // Robust vertical centering fallback
  &::after {
    content: "";
    display: inline-block;
    height: 100%;
    vertical-align: middle;
  }

  & .sidebar-logo-link {
    height: 60px;
    width: 100%;
    display: flex;
    flex-direction: row;
    align-items: center;
    justify-content: center;

    & .sidebar-logo-icon {
      width: 32px;
      height: 32px;
      display: block;
      flex: none;
      border-radius: 7px;
      object-fit: cover;
    }

    & .logo-wrapper {
      height: 100%;
      width: 100%;
      display: flex;
      align-items: center;
      justify-content: flex-start;
      gap: 10px;
      padding: 0 16px;
    }

    & .sidebar-title {
      margin: 0;
      color: var(--text-primary);
      font-weight: 650;
      font-size: 14px;
      font-family: var(--font-sans);
      letter-spacing: 0;
      white-space: nowrap;
    }
  }

  &.collapse {
    .sidebar-logo-link {
        padding: 0;
        justify-content: center;
    }
  }
}
</style>
