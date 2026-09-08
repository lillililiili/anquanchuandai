<script setup lang="ts">
import { onMounted, ref, unref } from 'vue'
import { ElSelect, ElOption } from 'element-plus'
import { getSingleDict } from '@/utils/dict'

interface OptionItem {
  value: string | number
  label: string | number
  disabled?: boolean
}

const props = defineProps<{
  dict?: string
  options?: OptionItem[]
  loading?: boolean
  apiFun?: () => Promise<OptionItem[]>
}>()

const dataOptions = ref<any[]>([])

const loadLoading = ref(false)

onMounted(() => {
  if (props.dict) {
    getSingleDict(props.dict).then(res => {
      dataOptions.value = res
    })
  } else if (props.options) {
    dataOptions.value = props.options || []
  } else if (props.apiFun) {
    loadLoading.value = true
    props
      .apiFun()
      .then(res => {
        dataOptions.value = res
      })
      .catch(e => {
        console.error('ele-select组件获取数据失败', e)
        dataOptions.value = []
      })
      .finally(() => {
        loadLoading.value = false
      })
  }
})
</script>

<template>
  <ElSelect v-bind="$attrs">
    <ElOption
      v-for="item in dataOptions"
      v-if="dict || options || apiFun"
      :key="item.value"
      :label="item.label"
      :value="item.value"
    />
    <slot v-else />
  </ElSelect>
</template>

<style lang="scss" scoped></style>
