<script setup>
import UiIcon from '@ui-spec/UiIcon.vue'
defineProps({name:{type:String,required:true},color:{type:String,default:''}})
</script>
<template><UiIcon :name="name" :class="color" /></template>
