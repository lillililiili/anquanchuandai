<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { ElSelect, ElOption } from 'element-plus'
import { getSingleDict } from '@/utils/dict'

interface OptionItem {
  value: string | number
  label: string | number
  disabled?: boolean
}

const props = defineProps<{
  modelValue?: string | number
  dict?: string
  options?: OptionItem[]
  loading?: boolean
}>()

const dataOptions = ref<any[]>([])

onMounted(() => {
  if (props.dict) {
    getSingleDict(props.dict).then(res => {
      dataOptions.value = res
    })
  } else {
    dataOptions.value = props.options || []
  }
})

const dictValue = computed(() => {
  return `${props.modelValue}`
})
</script>

<template>
  <ElSelect :modelValue="dictValue" v-bind="$attrs">
    <ElOption
      v-for="item in dataOptions"
      v-if="dict || options"
      :key="`${item.value}`"
      :label="item.label"
      :value="`${item.value}`"
    />
    <slot v-else />
  </ElSelect>
</template>

<style lang="scss" scoped></style>
