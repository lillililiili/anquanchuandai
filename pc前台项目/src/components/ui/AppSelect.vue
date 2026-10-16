<script setup>
import UiSelect from '@ui-spec/UiSelect.vue'
defineProps({modelValue:{type:[String,Number,Array],default:''},options:{type:Array,default:()=>[]},name:{type:String,default:''},disabled:Boolean,ariaLabel:{type:String,default:''}})
defineEmits(['update:modelValue'])
</script>
<template>
  <UiSelect :model-value="modelValue" :options="options" :name="name || undefined" :disabled="disabled" :aria-label="ariaLabel || undefined" @update:model-value="$emit('update:modelValue',$event)">
    <template v-if="$slots.trigger" #trigger="props"><slot name="trigger" v-bind="props" /></template>
  </UiSelect>
</template>
