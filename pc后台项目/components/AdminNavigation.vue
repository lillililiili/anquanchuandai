<script setup>
import { computed, nextTick, onMounted, onBeforeUnmount, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { MENU, menuPath } from '../navigation'
import { fitAdminNavigation } from '../adminNavigation'
import { usePopup } from '@ui-spec/usePopup'
import { TEST_SITE_MODE, TEST_SITE } from '../../shared/test-site.mjs'
const props = defineProps({ sites: Array, siteId: String, identity: Object, portal: String, switching: Boolean })
const emit = defineEmits(['site', 'logout'])
const route = useRoute(), active = computed(() => menuPath(route.path))
const root = ref(), leftSlot = ref(), rightSlot = ref(), measure = ref(), more = ref(), popup = ref()
const visibleCount = ref(MENU.length), leftCount = ref(2), opened = ref(false), accountTrigger = ref()
const account = usePopup(accountTrigger, { width: 220 })
const { open: accountOpen, panel: accountPanel, target: accountTarget, position: accountPosition } = account
const name = computed(() => props.identity?.name?.trim() || '当前账号')
const initial = computed(() => Array.from(name.value)[0])
const station = computed(() => props.sites?.find(s => s.id === props.siteId)?.name || '无授权厂站')
const left = computed(() => MENU.slice(0, leftCount.value)), right = computed(() => MENU.slice(leftCount.value, visibleCount.value))
const overflow = computed(() => MENU.slice(visibleCount.value)), overflowActive = computed(() => overflow.value.find(item => item.path === active.value))
const target = path => ({ path, query: props.siteId ? { siteId: props.siteId } : {} })
let observer, frame, disposed = false
function close(restore = false) { opened.value = false; if (restore) more.value?.focus() }
function resize() {
  cancelAnimationFrame(frame)
  frame = requestAnimationFrame(() => {
    if (!measure.value) return
    const widths = [...measure.value.querySelectorAll('[data-measure-item]')].map(el => el.getBoundingClientRect().width)
    const next = fitAdminNavigation(widths, leftSlot.value.clientWidth, rightSlot.value.clientWidth, measure.value.querySelector('[data-measure-more]').getBoundingClientRect().width)
    if ((next.visibleCount !== visibleCount.value || next.leftCount !== leftCount.value) && opened.value) close(true)
    visibleCount.value = next.visibleCount; leftCount.value = next.leftCount
  })
}
async function openMore(last = false) {
  account.close(); opened.value = true; await nextTick()
  const links = popup.value?.querySelectorAll('a'); (last ? links?.[links.length - 1] : links?.[0])?.focus()
}
function menuKey(event) {
  const links = [...popup.value.querySelectorAll('a')], index = links.indexOf(document.activeElement)
  if (event.key === 'Escape') { event.preventDefault(); close(true) }
  else if (['ArrowDown','ArrowUp','Home','End'].includes(event.key)) {
    event.preventDefault()
    const next = event.key === 'Home' ? 0 : event.key === 'End' ? links.length - 1 : (index + (event.key === 'ArrowDown' ? 1 : -1) + links.length) % links.length
    links[next]?.focus()
  }
}
async function openAccount() { close(); if (accountOpen.value) account.close(true); else { await account.show(); await nextTick(); accountPanel.value?.querySelector('button')?.focus() } }
function outside(event) { if (!root.value?.contains(event.target)) close() }
watch(() => route.fullPath, () => { close(); account.close() })
onMounted(() => {
  observer = new ResizeObserver(resize); observer.observe(root.value); observer.observe(measure.value)
  document.addEventListener('pointerdown', outside)
  document.fonts.ready.then(() => { if (!disposed) resize() }); resize()
})
onBeforeUnmount(() => { disposed = true; observer?.disconnect(); cancelAnimationFrame(frame); document.removeEventListener('pointerdown', outside) })
</script>
<template>
  <nav ref="root" class="admin-navigation" aria-label="主导航" @focusout="!root?.contains($event.relatedTarget) && close()">
    <div class="admin-nav-tools" role="group" aria-label="前台入口与厂站">
      <a v-if="portal" class="admin-tool" :href="portal" target="_blank" rel="noopener noreferrer" aria-label="打开监护前台" data-tooltip="打开监护前台"><UiIcon name="dashboard" /></a>
      <button v-else class="admin-tool" disabled aria-label="前台地址未配置"><UiIcon name="dashboard" /></button>
      <span v-if="TEST_SITE_MODE" class="admin-test-site" :aria-label="'当前厂区：' + station">{{ TEST_SITE.name }}</span>
      <span v-else class="admin-station-tool" :data-tooltip="'切换厂站：' + station">
        <UiSelect :model-value="siteId" :options="sites.map(s => [s.id,s.name])" :disabled="!sites.length || switching" :aria-label="'选择厂站，当前：' + station" @update:model-value="emit('site', $event)">
          <template #trigger><UiIcon name="building" /><UiIcon class="admin-tool-caret" name="chevron-down" /></template>
        </UiSelect>
      </span>
    </div>
    <div ref="leftSlot" class="admin-nav-side admin-nav-left"><router-link v-for="item in left" :key="item.path" class="admin-nav-item" :class="{active:active===item.path}" :to="target(item.path)" :aria-current="active===item.path?'page':undefined">{{item.title}}</router-link></div>
    <router-link class="admin-title" :to="target('/devices')" aria-label="智能穿戴设备平台 · 管理中心，返回设备台账"><span>智能穿戴设备平台 · 管理中心</span></router-link>
    <div ref="rightSlot" class="admin-nav-side admin-nav-right">
      <router-link v-for="item in right" :key="item.path" class="admin-nav-item" :class="{active:active===item.path}" :to="target(item.path)" :aria-current="active===item.path?'page':undefined">{{item.title}}</router-link>
      <div v-if="overflow.length" class="admin-nav-more">
        <button ref="more" class="admin-nav-item" :class="{active:overflowActive}" :aria-label="overflowActive?'更多菜单，当前：'+overflowActive.title:'更多菜单'" aria-haspopup="menu" :aria-expanded="opened" aria-controls="admin-more-menu" @click="opened?close():openMore()" @keydown.down.prevent="openMore()" @keydown.up.prevent="openMore(true)" @keydown.esc.prevent="close(true)">更多<UiIcon name="chevron-down" /></button>
        <div v-if="opened" id="admin-more-menu" ref="popup" class="admin-nav-popup" role="menu" aria-label="更多管理菜单" @keydown="menuKey"><router-link v-for="item in overflow" :key="item.path" role="menuitem" :to="target(item.path)" :class="{active:active===item.path}" :aria-current="active===item.path?'page':undefined">{{item.title}}</router-link></div>
      </div>
    </div>
    <div class="admin-nav-tools admin-nav-tools-right"><button ref="accountTrigger" class="admin-tool admin-avatar" :aria-label="'账号：'+name" :data-tooltip="name" aria-haspopup="true" :aria-expanded="accountOpen" @click="openAccount" @keydown.down.prevent="openAccount">{{initial}}</button></div>
    <div ref="measure" class="admin-nav-measure" aria-hidden="true" inert><span v-for="item in MENU" :key="item.path" class="admin-nav-item" data-measure-item>{{item.title}}</span><span class="admin-nav-item" data-measure-more>更多<UiIcon name="chevron-down" /></span></div>
  </nav>
  <Teleport :to="accountTarget"><div v-if="accountOpen" ref="accountPanel" class="ui-popup admin-account-popup" :style="accountPosition"><strong>{{name}}</strong><span class="muted">{{identity?.loginName}}</span><button class="button text-button" @click="account.close(true); emit('logout')"><UiIcon name="arrow-right" />退出登录</button></div></Teleport>
</template>

<style scoped>
.admin-test-site { flex: 0 0 36px; width: 36px; text-align: center; font-size: 13px; line-height: 16px; }
</style>
