<script setup lang="ts">
import { ref, computed } from 'vue'

const props = defineProps({
  imgs: {
    type: Array,
    default: () => []
  }
})

const imgDialogVisible = ref(false)

const fileList = computed(() => {
  return props.imgs.map(e => {
    // @ts-ignore
    return import.meta.env.VITE_APP_BASE_API + e
  })
})

function showImgDialog() {
  imgDialogVisible.value = true
}
</script>

<template>
  <div class="col">
    <el-button icon="Picture" link type="primary" @click="showImgDialog">
      {{ imgs.length }}
    </el-button>

    <el-dialog v-model="imgDialogVisible" append-to-body title="图片预览">
      <div class="flex gap-10px">
        <el-image
          v-for="(item, index) in fileList"
          :key="index"
          fit="cover"
          :initial-index="index"
          :preview-src-list="fileList"
          :src="item"
          style="width: 100px; height: 100px"
          :zoom-rate="1.2"
        />
      </div>
    </el-dialog>
  </div>
</template>

<style lang="less" scoped></style>
