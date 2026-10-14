<script setup>
const props=defineProps({modelValue:Boolean, disabled:Boolean, name:String})
const emit=defineEmits(['update:modelValue','change'])
function change(e){emit('update:modelValue',e.target.checked);emit('change',e)}
</script>
<template><input class="ui-switch" type="checkbox" role="switch" :name="name" :checked="modelValue" :disabled="disabled" @change="change" /></template>
