<template>
  <button class="sidebar-toggle" :aria-expanded="isActive" :aria-label="isActive ? '收起侧栏' : '展开侧栏'" type="button" @click="toggleClick">
    <svg
      class="hamburger"
      :class="{ 'is-active': isActive }"
      aria-hidden="true"
      height="20"
      viewBox="0 0 1024 1024"
      width="20"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="M408 442h480c4.4 0 8-3.6 8-8v-56c0-4.4-3.6-8-8-8H408c-4.4 0-8 3.6-8 8v56c0 4.4 3.6 8 8 8zm-8 204c0 4.4 3.6 8 8 8h480c4.4 0 8-3.6 8-8v-56c0-4.4-3.6-8-8-8H408c-4.4 0-8 3.6-8 8v56zm504-486H120c-4.4 0-8 3.6-8 8v56c0 4.4 3.6 8 8 8h784c4.4 0 8-3.6 8-8v-56c0-4.4-3.6-8-8-8zm0 632H120c-4.4 0-8 3.6-8 8v56c0 4.4 3.6 8 8 8h784c4.4 0 8-3.6 8-8v-56c0-4.4-3.6-8-8-8zM142.4 642.1L298.7 519a8.84 8.84 0 0 0 0-13.9L142.4 381.9c-5.8-4.6-14.4-.5-14.4 6.9v246.3a8.9 8.9 0 0 0 14.4 7z"
      />
    </svg>
  </button>
</template>

<script setup>
defineProps({
  isActive: {
    type: Boolean,
    default: false
  }
})

const emit = defineEmits(['toggleClick'])
const toggleClick = () => {
  emit('toggleClick')
}
</script>

<style scoped>
.sidebar-toggle { display: inline-flex; align-items: center; justify-content: center; flex-shrink: 0; min-width: 36px; height: 36px; padding: 0; border: 0; color: var(--text-secondary); background: transparent; cursor: pointer; }
.hamburger {
  display: inline-block;
  vertical-align: middle;
  width: 20px;
  height: 20px;
  fill: currentColor;
}

.hamburger.is-active {
  transform: rotate(180deg);
}
</style>
