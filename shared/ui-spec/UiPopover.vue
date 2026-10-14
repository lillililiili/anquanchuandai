<script setup>
import { ref, nextTick } from 'vue'
import { usePopup } from './usePopup'
import UiIcon from './UiIcon.vue'
const props = defineProps({ label: { default:'更多' } })
const trigger=ref(null)
const {open,panel,target,position,show,close}=usePopup(trigger,{width:260})
async function toggle(){if(open.value)close(true);else{await show();await nextTick();panel.value?.querySelector('button:not(:disabled),a')?.focus()}}
function select(e){if(e.target.closest('button:not(:disabled),a'))close(true)}
</script>
<template><button ref="trigger" type="button" class="button" aria-label="更多操作" aria-haspopup="true" :aria-expanded="open" @click="toggle">{{label}}<UiIcon name="chevron-down" /></button><Teleport :to="target"><div v-if="open" ref="panel" class="ui-popup ui-action-popup" :style="position" @click="select"><slot /></div></Teleport></template>
