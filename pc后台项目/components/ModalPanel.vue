<template>
  <dialog ref="dialog" :aria-labelledby="headingId" class="modal-panel ui-dialog admin-sketch-dialog" :data-dialog-size="dialogSize(size)" :data-dialog-layout="layout" @cancel.prevent="close" @click="backdrop">
    <header><h2 :id="headingId"><span>{{ title }}</span></h2><button type="button" aria-label="关闭弹窗" class="button modal-close" @click="close"><span aria-hidden="true" /></button></header>
    <div class="modal-content"><slot /></div>
    <footer v-if="$slots.footer" class="dialog-footer"><slot name="footer" /></footer>
  </dialog>
</template>
<script setup>
import { ref, watch, nextTick, onBeforeUnmount } from 'vue'
import { dialogSize, restoreDialogFocus } from '@ui-spec/dialog'
import '../styles/admin-dialog.css'
const props = defineProps({ open: Boolean, size: String, layout: { type: String, default: 'content' }, title: String, headingId: { type: String, default: 'panel-heading' } })
const emit = defineEmits(['close'])
const dialog = ref(null)
let previousFocus
function close() { emit('close') }
function backdrop(event) { if (event.target === dialog.value) { const r = dialog.value.getBoundingClientRect(); if (event.clientX < r.left || event.clientX > r.right || event.clientY < r.top || event.clientY > r.bottom) close() } }
watch(() => props.open, async value => {
  await nextTick()
  if (!dialog.value) return
  if (value) { previousFocus = document.activeElement; if (!dialog.value.open) dialog.value.showModal() }
  else if (dialog.value?.open) { dialog.value.close(); restoreDialogFocus(previousFocus) }
}, { immediate: true })
onBeforeUnmount(() => dialog.value?.close())
</script>
