<template>
  <ModalPanel :open="!!confirmation" class="confirmation-dialog" size="confirm" heading-id="discard-confirmation-heading" :title="confirmation?.title" @close="finishConfirmation(false)">
    <template v-if="confirmation">
      <p class="confirmation-message">{{ confirmation.message }}</p>
    </template>
    <template v-if="confirmation" #footer>
        <button class="button" type="button" autofocus @click="finishConfirmation(false)">{{ confirmation.cancelText }}</button>
        <button class="button danger" type="button" @click="finishConfirmation(true)">{{ confirmation.confirmText }}</button>
    </template>
  </ModalPanel>
</template>
<script setup>
import ModalPanel from './ModalPanel.vue'
import { confirmation, finishConfirmation } from '../confirmation'
</script>
<style>
.modal-panel.confirmation-dialog { width: min(440px, calc(100vw - 32px)); }
.confirmation-message { margin: 0 0 24px; line-height: 1.7; }
.confirmation-actions { display: flex; justify-content: flex-end; gap: 12px; flex-wrap: wrap; }
</style>
