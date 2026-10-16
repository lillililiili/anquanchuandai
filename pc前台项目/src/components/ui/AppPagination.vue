<script setup>
import { computed } from "vue";
import AppButton from "./AppButton.vue";
import AppSelect from "./AppSelect.vue";
import { clampPage, pageCount, pageNumbers } from "@/lib/pagination";

const props = defineProps({
  total: { type: Number, default: 0 },
  modelValue: { type: Number, default: 1 },
  pageSize: { type: Number, default: 10 },
});
const emit = defineEmits(["update:modelValue", "update:pageSize"]);
const count = computed(() => pageCount(props.total, props.pageSize));
const current = computed(() => clampPage(props.modelValue, props.total, props.pageSize));
const numbers = computed(() => pageNumbers(current.value, count.value));
const sizes = [[10, "10 条/页"], [20, "20 条/页"], [50, "50 条/页"]];
function go(page) {
  emit("update:modelValue", clampPage(page, props.total, props.pageSize));
}
</script>

<template>
  <nav class="pagination" aria-label="表格分页">
    <div class="pagination-summary">
      <span aria-live="polite">共 {{ total }} 条</span>
      <AppSelect :model-value="pageSize" :options="sizes" aria-label="每页条数" @update:model-value="emit('update:pageSize', Number($event))" />
    </div>
    <div class="pagination-pages">
      <AppButton icon="arrow-left-s-line" aria-label="上一页" :disabled="current === 1" @click="go(current - 1)" />
      <template v-for="number in numbers" :key="number">
        <span v-if="typeof number === 'string'" class="pagination-gap" aria-hidden="true">…</span>
        <AppButton v-else :tone="current === number ? 'primary' : ''" :aria-label="'第 ' + number + ' 页'" :aria-current="current === number ? 'page' : undefined" @click="go(number)">{{ number }}</AppButton>
      </template>
      <AppButton icon="arrow-right-s-line" aria-label="下一页" :disabled="current === count" @click="go(current + 1)" />
    </div>
  </nav>
</template>
