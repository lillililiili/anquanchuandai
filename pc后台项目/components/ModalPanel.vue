<template>
  <dialog ref="dialog" :aria-labelledby="headingId" class="modal-panel" :class="{ 'side-panel': side }" @cancel.prevent="close" @click="backdrop">
    <header><div><span class="eyebrow">管理中心 / 演示数据</span><h2 :id="headingId">{{ title }}</h2></div><button aria-label="关闭面板" class="button" @click="close">关闭</button></header>
    <div class="modal-content"><slot /></div>
  </dialog>
</template>
<script setup>
import { ref, watch, nextTick, onBeforeUnmount } from 'vue'
const props = defineProps({ open: Boolean, side: Boolean, title: String, headingId: { type: String, default: 'panel-heading' } })
const emit = defineEmits(['close'])
const dialog = ref(null)
let previousFocus
function close() { emit('close') }
function backdrop(event) { if (event.target === dialog.value) { const r = dialog.value.getBoundingClientRect(); if (event.clientX < r.left || event.clientX > r.right || event.clientY < r.top || event.clientY > r.bottom) close() } }
watch(() => props.open, async value => {
  await nextTick()
  if (!dialog.value) return
  if (value) { previousFocus = document.activeElement; if (!dialog.value.open) dialog.value.showModal() }
  else if (dialog.value?.open) { dialog.value.close(); previousFocus?.focus?.() }
}, { immediate: true })
onBeforeUnmount(() => dialog.value?.close())
</script>
