<script setup>
import AppIcon from '@/components/ui/AppIcon.vue';
defineProps({ notices: { type: Array, default: () => [] } });
const emit = defineEmits(['open', 'open-all', 'dismiss', 'dismiss-all']);
</script>

<template>
  <aside v-if="notices.length" class="fence-notices" aria-label="围栏进出提醒">
    <header class="fence-notices-heading">
      <AppIcon name="notification-3-line" />
      <strong>围栏进出提醒</strong><span>{{ notices.length }} 条</span>
      <button type="button" class="fence-notice-close" aria-label="关闭所有围栏提醒" @click="emit('dismiss-all')"><AppIcon name="close-line" /></button>
    </header>
    <div class="fence-notices-list" aria-live="polite" aria-relevant="additions">
      <article v-for="item in notices.slice(0, 3)" :key="item.id" class="fence-notice">
        <div class="fence-notice-copy">
          <p><strong>{{ item.snapshot?.personName || '关联人员' }}</strong> {{ item.fenceDirection }}围栏</p>
          <p class="fence-notice-name">{{ item.fenceName }}</p>
          <time>{{ item.date }} {{ item.time }}</time>
        </div>
        <button type="button" class="fence-notice-open" @click="emit('open', item)">查看告警 <span aria-hidden="true">→</span></button>
        <button type="button" class="fence-notice-dismiss" :aria-label="'关闭' + (item.snapshot?.personName || '') + item.fenceDirection + '围栏提醒'" @click="emit('dismiss', item.id)"><AppIcon name="close-line" /></button>
      </article>
    </div>
    <footer><span>{{ notices.length > 3 ? `另有 ${notices.length - 3} 条进出提醒` : '已同步至通知和告警列表' }}</span><button type="button" @click="emit('open-all')">全部围栏告警</button></footer>
  </aside>
</template>

<style scoped>
.fence-notices { position: fixed; right: 24px; bottom: 24px; width: min(400px, calc(100vw - 32px)); z-index: 900; border: 1px solid #4b96bb; border-top: 3px solid #ffc36a; border-radius: 12px; background: #102c40; color: #e8f4ff; box-shadow: 0 12px 40px #0006; overflow: hidden; }
.fence-notices-heading { display: flex; align-items: center; gap: 10px; padding: 12px 16px; background: #193b53; }
.fence-notices-heading > .ui-icon { color: #ffc36a; }
.fence-notices-heading > span { color: #b8cddd; font-size: 12px; }
.fence-notices button { font: inherit; cursor: pointer; }
.fence-notices button:focus-visible { outline: 2px solid #76eaff; outline-offset: -2px; }
.fence-notice-close, .fence-notice-dismiss { display: grid; place-items: center; border: 0; background: transparent; color: #c7dce9; width: 32px; height: 32px; }
.fence-notice-close { margin-left: auto; }
.fence-notices-list { max-height: 50vh; overflow-y: auto; }
.fence-notice { position: relative; display: flex; align-items: center; gap: 16px; padding: 18px 36px 18px 18px; border-bottom: 1px solid #315168; }
.fence-notice-copy { flex: 1; min-width: 0; }
.fence-notice p { margin: 0; line-height: 1.6; overflow-wrap: anywhere; }
.fence-notice-name { color: #a6eaff; }
.fence-notice time { display: block; margin-top: 6px; color: #b2c6d5; font-size: 12px; }
.fence-notice-open { flex-shrink: 0; border: 0; background: transparent; color: #91e8ff; padding: 8px 0; font-size: 13px !important; }
.fence-notice-dismiss { position: absolute; top: 4px; right: 2px; }
.fence-notices footer { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 12px 16px; font-size: 12px; color: #b2c6d5; }
.fence-notices footer button { border: 0; background: transparent; color: #91e8ff; padding: 4px 0; }
@media (max-width: 600px) { .fence-notices { right: 16px; bottom: 16px; } }
</style>
