<template>
  <el-dialog
    v-model="visible"
    append-to-body
    class="agora-video-dialog"
    :show-close="true"
    :title="title"
    width="1200px"
    @close="handleClose"
  >
    <div class="video-wrapper">
      <div class="video-container" ref="videoContainerRef">
        <!-- 右上角信息标签 -->
        <div class="video-overlay-tags">
          <div class="monitor-tag monitor-tag-device" v-if="deviceNo">
            {{ deviceNo }}
          </div>
          <div class="monitor-tag monitor-tag-user" v-if="userName">
            {{ userName }}
          </div>
          <div class="monitor-tag monitor-tag-hangup" @click="handleHangup">
            <el-icon><Phone /></el-icon>
          </div>
        </div>

        <!-- 声网视频播放区域 -->
        <div id="agora-video-player" class="agora-video-player"></div>

        <!-- 无连接时显示提示 -->
        <div v-if="!isConnected" class="video-content">
          <el-icon class="loading-icon is-rotating"><Loading /></el-icon>
          <span class="center-text">正在建立音视频连接...</span>
          <span class="sub-text">请稍候，正在加入频道</span>
        </div>

        <!-- 已连接但无远端用户时显示提示 -->
        <div v-else-if="isConnected && !hasRemoteUsers" class="video-content">
          <el-icon class="waiting-icon"><Timer /></el-icon>
          <span class="center-text">等待设备推流...</span>
          <span class="sub-text">已成功加入频道，等待远端设备接入</span>
        </div>
      </div>
    </div>
  </el-dialog>
</template>

<script setup lang="ts">
import { Loading, Timer, Phone } from '@element-plus/icons-vue'
import { useAgoraRtc } from '@/hooks/useAgoraRtc'
import type { AgoraCredentials } from '@/hooks/useAgoraRtc'
import { ref, watch, computed, nextTick } from 'vue'

const props = defineProps({
  /** 控制弹窗显示 */
  modelValue: {
    type: Boolean,
    default: false
  },
  /** 弹窗标题 */
  title: {
    type: String,
    default: '详情'
  },
  /** 声网凭证 */
  credentials: {
    type: Object as () => AgoraCredentials,
    default: null
  },
  /** 是否回放模式 */
  isPlayback: {
    type: Boolean,
    default: false
  },
  /** 帽子编号 */
  deviceNo: {
    type: String,
    default: ''
  },
  /** 绑定人员姓名 */
  userName: {
    type: String,
    default: ''
  }
})

const emit = defineEmits(['update:modelValue', 'hangup', 'replay', 'error', 'connected', 'credentials-clear'])

// 内部可见状态
const visible = computed({
  get: () => props.modelValue,
  set: (val) => emit('update:modelValue', val)
})

const videoContainerRef = ref(null)

// 使用声网 composable
const {
  isConnected,
  remoteUsers,
  hasRemoteUsers,
  initClient,
  cleanup,
  playRemoteVideo
} = useAgoraRtc({
  onError: (error) => {
    emit('error', error)
  },
  onConnected: () => {
    emit('connected')
  }
})

// 监听凭证变化，自动初始化
watch(
  () => props.credentials,
  async (newCredentials) => {
    if (newCredentials && props.modelValue) {
      await initClient(newCredentials)
      // 等待连接成功后播放远端视频
      if (isConnected.value) {
        nextTick(() => {
          remoteUsers.value.forEach((_, uid) => {
            playRemoteVideo(uid, 'agora-video-player')
          })
        })
      }
    }
  },
  { immediate: true }
)

// 监听弹窗关闭
watch(visible, async (val) => {
  if (!val) {
    await cleanup()
  }
})

// 监听新远端用户加入，自动播放视频
watch(remoteUsers, (newMap) => {
  if (!visible.value || !isConnected.value) return

  nextTick(() => {
    newMap.forEach((userInfo, uid) => {
      if (userInfo.hasVideo && userInfo.videoTrack) {
        playRemoteVideo(uid, 'agora-video-player')
      }
    })
  })
})

// 挂断/关闭
async function handleHangup() {
  await cleanup()
  emit('hangup')
  visible.value = false
}

// 弹窗关闭处理
async function handleClose() {
  await cleanup()
  emit('credentials-clear')
}

// 暴露方法供外部调用
defineExpose({
  initClient,
  cleanup,
  isConnected,
  remoteUsers
})
</script>

<style scoped lang="scss">
@import "@/assets/styles/variables.module.scss";

.agora-video-dialog {
  :deep(.el-dialog) {
    background: transparent !important;
    box-shadow: none !important;
    border-radius: 12px;
    overflow: hidden;
    margin-top: 5vh !important;

    .el-dialog__header {
      display: block;
      padding: var(--space-4) var(--section-padding);
      position: absolute;
      top: 0;
      left: 0;
      right: 0;
      z-index: 20;
      background: rgba(15, 23, 33, 0.92);
      border-bottom: 1px solid rgba(255, 255, 255, 0.1);

      .el-dialog__title {
        color: #fff;
        font-size: var(--text-lg);
        font-weight: var(--font-bold);
      }

      .el-dialog__headerbtn {
        top: var(--space-4);
        right: var(--section-padding);
        width: 32px;
        height: 32px;

        .el-dialog__close {
          color: rgba(255, 255, 255, 0.8) !important;
          font-size: var(--text-2xl);

          &:hover {
            color: #fff !important;
          }
        }
      }
    }

    .el-dialog__body {
      padding: 0;
      background: #333 !important;
    }

    .el-dialog__footer {
      display: none;
    }
  }
}

.video-wrapper {
  position: relative;
  width: 100%;
  background: #333;
}

.video-container {
  width: 100%;
  aspect-ratio: 16 / 9;
  display: flex;
  align-items: center;
  justify-content: center;
  background: #2a2a2a;
  position: relative;

  // 右上角标签样式
  .video-overlay-tags {
    position: absolute;
    top: var(--space-3);
    right: var(--space-3);
    display: flex;
    align-items: center;
    gap: 8px;
    z-index: 30;
    pointer-events: auto;

    .monitor-tag {
      height: 28px;
      padding: 0 var(--space-3);
      border-radius: 14px;
      font-size: var(--text-sm);
      font-weight: var(--font-medium);
      display: flex;
      align-items: center;
      justify-content: center;
      white-space: nowrap;
      max-width: 180px;
      overflow: hidden;
      text-overflow: ellipsis;
    }

    .monitor-tag-device {
      background: rgba(30, 41, 59, 0.92);
      color: #f8fafc;
      border: 1px solid rgba(148, 163, 184, 0.2);
    }

    .monitor-tag-user {
      background: rgba(30, 41, 59, 0.92);
      color: #cbd5e1;
      border: 1px solid rgba(148, 163, 184, 0.2);
    }

    .monitor-tag-hangup {
      width: 28px;
      height: 28px;
      min-width: 28px;
      padding: 0;
      display: flex;
      align-items: center;
      justify-content: center;
      cursor: pointer;
      background: rgba(220, 38, 38, 0.72);
      border: 1px solid rgba(220, 38, 38, 0.3);
      color: rgba(255, 255, 255, 0.9);
      border-radius: 50%;
      transition: all 0.2s ease;

      &:hover {
        background: rgba(220, 38, 38, 0.92);
        transform: translateY(-1px);
      }

      .el-icon {
        font-size: 14px;
      }
    }
  }

  .video-content {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: var(--space-4);

    .loading-icon,
    .waiting-icon {
      font-size: 48px;
      color: var(--color-primary);
    }

    .loading-icon {
      animation: rotating 2s linear infinite;
    }

    .center-text {
      color: #fff;
      font-size: var(--text-2xl);
      font-weight: var(--font-bold);
      letter-spacing: var(--tracking-wider);
    }

    .sub-text {
      color: rgba(255, 255, 255, 0.6);
      font-size: var(--text-base);
    }
  }
}

.agora-video-player {
  position: absolute;
  inset: 0;
  background: #000;
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;

  > div {
    width: 100% !important;
    height: 100% !important;
  }

  video {
    width: 100%;
    height: 100%;
    object-fit: contain;
  }
}

.video-container:fullscreen {
  width: 100vw;
  height: 100vh;

  .agora-video-player {
    max-width: 100%;
    max-height: 100%;
  }
}
</style>
