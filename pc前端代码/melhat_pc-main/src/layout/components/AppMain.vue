<template>
  <section class="app-main">
    <router-view v-slot="{ Component, route }">
      <transition mode="out-in" name="fade-transform">
        <keep-alive :include="tagsViewStore.cachedViews">
          <div>
            <component
              :is="Component"
              v-if="!route.meta.link"
              :key="route.path"
            />
          </div>
        </keep-alive>
      </transition>
    </router-view>
    <iframe-toggle />
  </section>
</template>

<script setup>
import useTagsViewStore from "@/store/modules/tagsView";
import iframeToggle from "./IframeToggle/index";

const tagsViewStore = useTagsViewStore();
</script>

<style lang="scss" scoped>
.app-main {
  width: 100%;
  position: relative;
  overflow-y: auto;
  background-color: var(--bg-base);
  // The shell uses a single compact fixed header.
  height: calc(100vh - 56px);
  margin-top: 56px;
  scrollbar-gutter: stable;
}
</style>

<style lang="scss">
// fix css style bug in open el-dialog
.el-popup-parent--hidden {
  .fixed-header {
    padding-right: 6px;
  }
}

::-webkit-scrollbar {
  width: 8px;
  height: 8px;
}

::-webkit-scrollbar-track {
  background-color: transparent;
}

::-webkit-scrollbar-thumb {
  border: 2px solid transparent;
  border-radius: 8px;
  background-color: color-mix(in srgb, var(--text-muted) 58%, transparent);
  background-clip: padding-box;
}
</style>
