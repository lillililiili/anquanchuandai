<template>
  <el-config-provider :locale="locale" :size="size">
    <router-view />
  </el-config-provider>
  <!-- 异步加载视频组件，减少初始加载体积 -->
  <VideoView v-if="handler.visible.value" v-bind="handler.bindProps" @close="onVideoClose" />
  <!-- 自定义告警通知组件 -->
  <AlarmNotification ref="alarmNotificationRef" />
</template>

<script setup>
import Cookies from 'js-cookie'
import zhCn from 'element-plus/es/locale/lang/zh-cn'
import { defineAsyncComponent, ref, provide } from 'vue'
import useSettingsStore from '@/store/modules/settings'
import { applyColorMode, handleThemeStyle } from '@/utils/theme'
import { useModalHandler } from '@/hooks/useModalHandler'
import AlarmNotification from '@/components/AlarmNotification/index.vue'

// 异步加载视频组件，仅在需要时加载（包含 flv-extend 等重型依赖）
const VideoView = defineAsyncComponent(() =>
  import('@/server/components/video-dialog.vue')
)

const alarmNotificationRef = ref(null)

// 提供全局告警通知方法
provide('alarmNotification', {
  show: (data) => {
    if (alarmNotificationRef.value) {
      alarmNotificationRef.value.show(data)
    }
  }
})

// 挂载到 window 供 WebSocket 使用
window.showAlarmNotification = (data) => {
  if (alarmNotificationRef.value) {
    alarmNotificationRef.value.show(data)
  }
}

// Element Plus 全局配置
const locale = ref(zhCn)
const size = computed(() => Cookies.get('size') || 'default')
const settingsStore = useSettingsStore()

applyColorMode('light')

const handler = useModalHandler()

window.onAssistVideo = data => {
  handler.showModal(data.msg)
}

function onVideoClose(e) {
  if (window.onAssistEnd) {
    window.onAssistEnd(e)
  } else {
    throw new Error('onAssistEnd is not defined')
  }
}

onMounted(() => {
  nextTick(() => {
    handleThemeStyle('#b45309')
  })
})
</script>
