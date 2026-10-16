<script setup>
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import AppIcon from '@/components/ui/AppIcon.vue';
import { fitNavigation, navigationItems as items, navigationOwner } from './navigation';

const route = useRoute();
const active = computed(() => navigationOwner(route.name));
const visibleCount = ref(items.length);
const leftCount = ref(4);
const left = computed(() => items.slice(0, leftCount.value));
const right = computed(() => items.slice(leftCount.value, visibleCount.value));
const overflow = computed(() => items.slice(visibleCount.value));
const overflowActive = computed(() => overflow.value.find(item => item.id === active.value));
const root = ref(); const leftSlot = ref(); const rightSlot = ref(); const measure = ref();
const more = ref(); const popup = ref(); const opened = ref(false);
let observer; let frame; let disposed = false;

function close(restore = false) {
  opened.value = false;
  if (restore) more.value?.focus();
}
function resize() {
  cancelAnimationFrame(frame);
  frame = requestAnimationFrame(() => {
    if (!measure.value) return;
    const widths = [...measure.value.querySelectorAll('[data-measure-item]')].map(el => el.getBoundingClientRect().width);
    const next = fitNavigation(widths, leftSlot.value.clientWidth, rightSlot.value.clientWidth, measure.value.querySelector('[data-measure-more]').getBoundingClientRect().width);
    if ((next.visibleCount !== visibleCount.value || next.leftCount !== leftCount.value) && opened.value) close(true);
    visibleCount.value = next.visibleCount;
    leftCount.value = next.leftCount;
  });
}
async function openMenu(last = false) {
  opened.value = true;
  await nextTick();
  const links = popup.value?.querySelectorAll('a');
  (last ? links?.[links.length - 1] : links?.[0])?.focus();
}
function onMenuKey(event) {
  const links = [...popup.value.querySelectorAll('a')];
  const index = links.indexOf(document.activeElement);
  if (event.key === 'Escape') { event.preventDefault(); close(true); }
  else if (['ArrowDown','ArrowUp','Home','End'].includes(event.key)) {
    event.preventDefault();
    const next = event.key === 'Home' ? 0 : event.key === 'End' ? links.length - 1 : (index + (event.key === 'ArrowDown' ? 1 : -1) + links.length) % links.length;
    links[next]?.focus();
  }
}
function onOutside(event) { if (!root.value?.contains(event.target)) close(); }
function onFocusOut(event) { if (!root.value?.contains(event.relatedTarget)) close(); }
watch(() => route.fullPath, () => close());
onMounted(() => {
  observer = new ResizeObserver(resize);
  observer.observe(root.value);
  observer.observe(measure.value);
  document.addEventListener('pointerdown', onOutside);
  document.fonts.ready.then(() => { if (!disposed) resize(); });
  resize();
});
onUnmounted(() => {
  disposed = true; observer?.disconnect(); cancelAnimationFrame(frame);
  document.removeEventListener('pointerdown', onOutside);
});
</script>

<template>
  <nav ref="root" class="portal-navigation" aria-label="业务导航" @focusout="onFocusOut">
    <div class="portal-nav-tools portal-nav-tools-left" role="group" aria-label="大屏与厂站"><slot name="left-tools" /></div>
    <div ref="leftSlot" class="portal-nav-side portal-nav-left">
      <a v-for="item in left" :key="item.id" class="portal-nav-item" :class="{ active: active === item.id }" :href="'#/' + item.id" :aria-current="active === item.id ? 'page' : undefined">{{ item.label }}</a>
    </div>
    <a class="portal-title" href="#/overview" aria-label="智能穿戴安全监护平台，返回综合总览"><span>智能穿戴安全监护平台</span></a>
    <div ref="rightSlot" class="portal-nav-side portal-nav-right">
      <a v-for="item in right" :key="item.id" class="portal-nav-item" :class="{ active: active === item.id }" :href="'#/' + item.id" :aria-current="active === item.id ? 'page' : undefined">{{ item.label }}</a>
      <div v-if="overflow.length" class="portal-nav-more">
        <button ref="more" type="button" class="portal-nav-item" :class="{ active: overflowActive }" :aria-label="overflowActive ? `更多菜单，当前：${overflowActive.label}` : '更多菜单'" aria-haspopup="menu" :aria-expanded="opened" aria-controls="portal-more-menu" @click="opened ? close() : openMenu()" @keydown.down.prevent="openMenu()" @keydown.up.prevent="openMenu(true)" @keydown.esc.prevent="close(true)">
          更多 <AppIcon name="arrow-down-s-line" />
        </button>
        <div v-if="opened" id="portal-more-menu" ref="popup" class="portal-nav-popup" role="menu" aria-label="更多业务菜单" @keydown="onMenuKey">
          <a v-for="item in overflow" :key="item.id" :href="'#/' + item.id" role="menuitem" :class="{ active: active === item.id }" :aria-current="active === item.id ? 'page' : undefined" @click="close()">{{ item.label }}</a>
        </div>
      </div>
    </div>
    <div class="portal-nav-tools portal-nav-tools-right" role="group" aria-label="通知与账号"><slot name="right-tools" /></div>
    <div ref="measure" class="portal-nav-measure" aria-hidden="true" inert>
      <span v-for="item in items" :key="item.id" data-measure-item class="portal-nav-item">{{ item.label }}</span>
      <span data-measure-more class="portal-nav-item">更多 <AppIcon name="arrow-down-s-line" /></span>
    </div>
  </nav>
</template>
