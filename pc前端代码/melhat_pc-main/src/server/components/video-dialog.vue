<script setup lang="ts">
import { reactive, watch, ref, onBeforeUnmount, shallowRef } from 'vue'
import FlvExtend from 'flv-extend'
import { useModalBinder } from '@/hooks/useModalBinder'

const props = withDefaults(
  defineProps<{
    videoUrl?: string
    title?: string
  }>(),
  {
    title: '远程协助'
  }
)

const emits = defineEmits(['close'])

const videoUrl = ref(props.videoUrl)

const isImportant = ref(false)

const modal = useModalBinder(url => {
  videoUrl.value = url
  isImportant.value = false
})

const videoElement = ref<HTMLVideoElement>()

const flvInstance = shallowRef<FlvExtend>()

const player = shallowRef<ReturnType<FlvExtend['init']>>()

const viewOpenHandle = () => {
  flvInstance.value = new FlvExtend({
    element: videoElement.value, // *必传
    frameTracking: true, // 开启追帧设置
    updateOnStart: true, // 点击播放后更新视频
    updateOnFocus: true, // 获得焦点后更新视频
    reconnect: true, // 开启断流重连
    reconnectInterval: 0 // 断流重连间隔
  })
  player.value = flvInstance.value.init(
    {
      type: 'flv',
      url: videoUrl.value,
      isLive: true
    },
    {
      enableStashBuffer: false, // 实时流播放，则设置为false
      autoCleanupSourceBuffer: true, // 对SourceBuffer进行自动清理
      stashInitialSize: 128, // 减少首帧显示等待时长
      enableWorker: true // 启用分离的线程进行转换
    }
  )
  player.value.play()
}

function close() {
  // modal.close()
  destroy()
  modal.hideModal()
  emits('close', isImportant.value)
}

defineExpose({
  showModal: modal.showModal
})

function destroy() {
  try {
    if (player.value) {
      player.value.pause()
      player.value.close()
      player.value = null
    }

    if (flvInstance.value) {
      flvInstance.value.destroy()
      flvInstance.value = null
    }
  } catch (e) {
    console.error(e)
  }
}

onBeforeUnmount(() => {
  destroy()
})
</script>

<template>
  <el-dialog
    :close-on-click-modal="false"
    :close-on-press-escape="false"
    :show-close="false"
    title="远程协助"
    v-bind="modal.bindProps"
    :z-index="2020"
    @opened="viewOpenHandle"
  >
    <video ref="videoElement" class="assist-video" controls></video>
    <template #footer>
      <div class="dialog-footer">
        <el-space class="ml-auto">
          <div class="">
            设为重要
            <el-switch v-model="isImportant" />
          </div>
          <el-button class="ml-10px" @click="close">结 束</el-button>
        </el-space>
      </div>
    </template>
  </el-dialog>
</template>

<style lang="scss" scoped>
.assist-video {
  width: 100%;
  height: 100%;
}
</style>
