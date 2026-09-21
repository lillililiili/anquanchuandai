<template>
  <ElPopover v-model:visible="visible" trigger="click" placement="bottom-end" :width="260" popper-class="admin-row-popover" :teleported="true">
    <template #reference><button ref="trigger" type="button" class="button" aria-label="更多操作">更多 ▾</button></template>
    <div class="row-more-content" @click="selectAction"><slot /></div>
  </ElPopover>
</template>
<script setup>
import { ref } from 'vue'
import { ElPopover } from 'element-plus'
import 'element-plus/es/components/popover/style/css'
const visible = ref(false), trigger = ref(null)
function selectAction(event) {
  if (!event.target.closest('button:not(:disabled), a')) return
  visible.value = false
  trigger.value?.focus()
}
</script>
