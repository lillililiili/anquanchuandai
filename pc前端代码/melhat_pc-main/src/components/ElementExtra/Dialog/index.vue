<script setup lang="ts">
import { reactive, watch, ref, useSlots } from 'vue'
import { ElDialog, ElDrawer } from 'element-plus'

const props = withDefaults(
  defineProps<{
    showCancel?: boolean
    okLoading?: boolean
    cancelLoading?: boolean
    okBtnText?: string
    cancelBtnText?: string
    showFooter?: boolean
  }>(),
  {
    showCancel: true,
    okLoading: false,
    cancelLoading: false,
    okBtnText: '确定',
    cancelBtnText: '取消',
    showFooter: true
  }
)

const emits = defineEmits(['cancel', 'ok'])

function onCancelClick() {
  emits('cancel')
}

function onOkClick() {
  emits('ok')
}

const slots = useSlots()
</script>

<template>
  <ElDrawer v-bind="$attrs" :size="$attrs.width" @close="onCancelClick">
    <template v-if="slots.header" #header>
      <slot name="header">
        {{ $attrs.title }}
      </slot>
    </template>
    <slot />
    <template #footer>
      <slot name="footer">
        <div v-if="showFooter" class="dialog-footer">
          <el-button
            :loading="props.okLoading"
            type="primary"
            @click="onOkClick"
          >
            {{ props.okBtnText }}
          </el-button>
          <el-button
            v-if="showCancel"
            :loading="props.cancelLoading"
            @click="onCancelClick"
          >
            {{ props.cancelBtnText }}
          </el-button>
        </div>
      </slot>
    </template>
  </ElDrawer>
</template>

<style lang="less" scoped></style>
