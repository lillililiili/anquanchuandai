<script setup>
import { computed } from 'vue'
import { clampPage, pageCount, pageNumbers } from '../pagination'
const props = defineProps({ total: { type:Number, default:0 }, modelValue: { type:Number, default:1 }, pageSize: { type:Number, default:10 }, disabled:Boolean })
const emit = defineEmits(['update:modelValue','update:pageSize'])
const count = computed(() => pageCount(props.total,props.pageSize)), current = computed(() => clampPage(props.modelValue,props.total,props.pageSize))
const numbers = computed(() => pageNumbers(current.value,count.value))
const sizes = computed(() => [...new Set([10,20,50,100,props.pageSize])].sort((a,b)=>a-b).map(n=>[n,`${n} 条/页`]))
function go(page) { emit('update:modelValue',clampPage(page,props.total,props.pageSize)) }
</script>
<template>
  <nav class="admin-pagination" aria-label="表格分页">
    <div class="admin-pagination-summary"><span aria-live="polite">共 {{total}} 条</span><UiSelect :model-value="pageSize" :options="sizes" :disabled="disabled" aria-label="每页条数" @update:model-value="emit('update:pageSize', Number($event))" /></div>
    <div class="admin-pagination-pages">
      <button type="button" class="button" :disabled="disabled || current===1" aria-label="上一页" @click="go(current-1)"><UiIcon name="chevron-left" /></button>
      <template v-for="number in numbers" :key="number"><span v-if="typeof number==='string'" aria-hidden="true">…</span><button v-else type="button" class="button" :class="{primary:current===number}" :disabled="disabled" :aria-label="`第 ${number} 页`" :aria-current="current===number?'page':undefined" @click="go(number)">{{number}}</button></template>
      <button type="button" class="button" :disabled="disabled || current===count" aria-label="下一页" @click="go(current+1)"><UiIcon name="chevron-right" /></button>
    </div>
  </nav>
</template>
