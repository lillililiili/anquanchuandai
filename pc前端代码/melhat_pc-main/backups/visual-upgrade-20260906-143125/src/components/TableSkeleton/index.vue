<template>
  <div class="table-skeleton">
    <div class="skeleton-row skeleton-header">
      <div v-for="n in columns" :key="n" class="skeleton-cell header-cell"></div>
    </div>
    <div v-for="row in rows" :key="row" class="skeleton-row">
      <div v-for="col in columns" :key="col" class="skeleton-cell body-cell"></div>
    </div>
  </div>
</template>

<script setup>
defineProps({
  rows: {
    type: Number,
    default: 5
  },
  columns: {
    type: Number,
    default: 6
  }
})
</script>

<style scoped>
.table-skeleton {
  width: 100%;
  border: 1px solid var(--border-color, #ebeef5);
  border-radius: var(--radius-lg, 10px);
  background: var(--bg-pure);
  overflow: hidden;
}

.skeleton-row {
  display: flex;
  border-bottom: 1px solid var(--border-color, #ebeef5);
}

.skeleton-row:last-child {
  border-bottom: none;
}

.skeleton-header {
  background: var(--bg-table-header);
}

.skeleton-cell {
  flex: 1;
  min-height: 40px;
  border-right: 1px solid var(--border-color, #ebeef5);
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 12px 10px;
}

.skeleton-cell:last-child {
  border-right: none;
}

.header-cell {
  height: 50px;
  background: var(--bg-muted);
  animation: skeleton-pulse 1.35s ease-in-out infinite;
}

.body-cell {
  height: 52px;
  background: var(--bg-soft);
  animation: skeleton-pulse 1.35s ease-in-out infinite;
}

@keyframes skeleton-pulse {
  0% {
    opacity: 0.55;
  }
  50% {
    opacity: 1;
  }
  100% {
    opacity: 0.55;
  }
}
</style>
