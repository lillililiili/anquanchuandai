import { ref, nextTick, onBeforeUnmount, type Ref } from 'vue'

/**
 * 声网音视频通话 Composable
 * 提供可复用的音视频连接、控制逻辑
 */

// 声明 AgoraRTC 全局类型
declare global {
  interface Window {
    AgoraRTC: any
  }
}

export interface AgoraCredentials {
  agoraAppId: string
  channelName: string
  agoraUid?: number | string
  agoraToken?: string
}

export interface RemoteUserInfo {
  hasAudio: boolean
  hasVideo: boolean
  audioMuted: boolean
  audioTrack?: any
  videoTrack?: any
}

export interface UseAgoraRtcOptions {
  /** 错误回调 */
  onError?: (error: Error) => void
  /** 连接成功回调 */
  onConnected?: () => void
  /** 用户加入回调 */
  onUserJoined?: (uid: number) => void
  /** 用户离开回调 */
  onUserLeft?: (uid: number) => void
  /** 是否发布本地音频，默认为 true */
  publishAudio?: boolean
  /** 是否创建本地麦克风轨道，默认为 true。设为 false 时不请求麦克风权限（纯查看场景） */
  enableLocalAudio?: boolean
  /** 视频容器父元素（可选），用于在容器不存在时自动创建 */
  playVideoContainer?: HTMLElement | null
}

export function useAgoraRtc(options: UseAgoraRtcOptions = {}) {
  // 声网客户端实例
  let agoraClient: any = null
  // 本地音频轨道
  let localAudioTrack: any = null

  // 状态
  const isConnected = ref(false)
  const isMicMuted = ref(false)
  const remoteUsers = ref(new Map<number, RemoteUserInfo>()) as Ref<Map<number, RemoteUserInfo>>
  const currentCredentials = ref<AgoraCredentials | null>(null)
  const isSecureContext = ref(window.isSecureContext)

  /**
   * 初始化声网客户端并加入频道
   */
  async function initClient(credentials: AgoraCredentials) {
    const AgoraRTC = window.AgoraRTC

    if (!AgoraRTC) {
      const error = new Error('未找到 AgoraRTC SDK')
      options.onError?.(error)
      return false
    }

    if (!credentials?.agoraAppId) {
      const error = new Error('缺少声网凭证信息')
      options.onError?.(error)
      return false
    }

    currentCredentials.value = credentials

    try {
      // 如果已有连接，先清理
      await cleanup()

      // 创建声网客户端
      agoraClient = AgoraRTC.createClient({ mode: 'rtc', codec: 'vp8' })

      // 监听远端用户事件
      agoraClient.on('user-published', handleUserPublished)
      agoraClient.on('user-unpublished', handleUserUnpublished)
      agoraClient.on('user-left', handleUserLeft)

      // 监听连接状态变化（断线重连等）
      agoraClient.on('connection-state-change', (_curState: string, prevState: string) => {
        console.log('Agora 连接状态变化:', prevState, '->', _curState)
      })

      // 监听 Token 过期（长连接需要）
      agoraClient.on('token-privilege-will-expire', async () => {
        console.warn('Agora Token 即将过期，需重新获取')
      })

      // 加入频道
      await agoraClient.join(
        credentials.agoraAppId,
        credentials.channelName,
        credentials.agoraToken || null,
        credentials.agoraUid || null
      )

      // 延迟后再检查已有远端用户（给服务器时间同步用户列表）
      await new Promise(r => setTimeout(r, 500))

      // 订阅已有远端用户
      const existingUsers = agoraClient.remoteUsers
      if (existingUsers) {
        const users = existingUsers instanceof Map ? Array.from(existingUsers.values()) : Object.values(existingUsers)
        for (const user of users) {
          if (user.hasAudio) await handleUserPublished(user, 'audio')
          if (user.hasVideo) await handleUserPublished(user, 'video')
        }
      }

      // 创建本地音频轨道（用于本地麦克风控制）
      const shouldEnableLocalAudio = options.enableLocalAudio !== false
      if (shouldEnableLocalAudio) {
        try {
          localAudioTrack = await AgoraRTC.createMicrophoneAudioTrack()
        } catch (err: any) {
          console.warn('麦克风启动失败:', err.message)
        }
      }

      // 根据配置决定是否发布本地音频
      const shouldPublishAudio = options.publishAudio !== false
      if (shouldPublishAudio && localAudioTrack) {
        await agoraClient.publish([localAudioTrack])
      }

      isConnected.value = true
      options.onConnected?.()
      return true
    } catch (err: any) {
      console.error('声网连接失败:', err)
      options.onError?.(err)
      await cleanup()
      return false
    }
  }

  /**
   * 处理远端用户发布流事件
   */
  async function handleUserPublished(user: any, mediaType: 'audio' | 'video') {
    if (!agoraClient) return

    await agoraClient.subscribe(user, mediaType)

    const uid = user.uid
    if (!remoteUsers.value.has(uid)) {
      remoteUsers.value.set(uid, { hasAudio: false, hasVideo: false, audioMuted: false })
    }

    const userInfo = remoteUsers.value.get(uid)!

    if (mediaType === 'video') {
      userInfo.hasVideo = true
      userInfo.videoTrack = user.videoTrack
    }

    if (mediaType === 'audio') {
      userInfo.hasAudio = true
      userInfo.audioTrack = user.audioTrack
      // 先停止可能存在的旧播放，避免重复 play 导致卡死
      userInfo.audioTrack.stop()
      userInfo.audioTrack.play()
    }

    remoteUsers.value = new Map(remoteUsers.value)
    options.onUserJoined?.(uid)
  }

  /**
   * 处理远端用户取消发布流事件
   */
  function handleUserUnpublished(user: any, mediaType: 'audio' | 'video') {
    const uid = user.uid
    const userInfo = remoteUsers.value.get(uid)
    if (!userInfo) return

    if (mediaType === 'video') {
      userInfo.hasVideo = false
      if (userInfo.videoTrack) {
        userInfo.videoTrack.stop()
      }
    }
    if (mediaType === 'audio') {
      userInfo.hasAudio = false
      if (userInfo.audioTrack) {
        userInfo.audioTrack.stop()
      }
    }

    remoteUsers.value = new Map(remoteUsers.value)
  }

  /**
   * 处理远端用户离开事件
   */
  function handleUserLeft(user: any) {
    const uid = user.uid
    const userInfo = remoteUsers.value.get(uid)
    if (userInfo) {
      if (userInfo.videoTrack) userInfo.videoTrack.stop()
      if (userInfo.audioTrack) userInfo.audioTrack.stop()
      remoteUsers.value.delete(uid)
      remoteUsers.value = new Map(remoteUsers.value)
      options.onUserLeft?.(uid)
    }
  }

  /**
   * 清理所有连接和资源
   */
  async function cleanup() {
    // 停止本地音频
    if (localAudioTrack) {
      localAudioTrack.stop()
      localAudioTrack.close()
      localAudioTrack = null
    }

    // 停止远端用户流
    remoteUsers.value.forEach((userInfo) => {
      if (userInfo.audioTrack) userInfo.audioTrack.stop()
      if (userInfo.videoTrack) userInfo.videoTrack.stop()
    })
    remoteUsers.value.clear()
    remoteUsers.value = new Map()

    // 离开频道
    if (agoraClient) {
      try {
        await agoraClient.leave()
      } catch (e) {
        console.warn('离开频道失败:', e)
      }
      agoraClient = null
    }

    isConnected.value = false
    isMicMuted.value = false
    currentCredentials.value = null
  }

  /**
   * 切换本地麦克风静音
   */
  function toggleMic() {
    if (!isSecureContext.value) {
      return false
    }
    if (!localAudioTrack) return false

    isMicMuted.value = !isMicMuted.value
    localAudioTrack.setMuted(isMicMuted.value)
    return true
  }

  /**
   * 切换远端用户静音
   */
  function toggleRemoteMute(uid: number) {
    const userInfo = remoteUsers.value.get(uid)
    if (!userInfo || !userInfo.audioTrack) return

    userInfo.audioMuted = !userInfo.audioMuted
    if (userInfo.audioMuted) {
      userInfo.audioTrack.stop()
    } else {
      userInfo.audioTrack.play()
    }
    remoteUsers.value = new Map(remoteUsers.value)
  }

  /**
   * 播放远端用户视频到指定容器
   */
  function playRemoteVideo(uid: number, containerId: string) {
    const userInfo = remoteUsers.value.get(uid)
    if (!userInfo?.videoTrack) return

    // 使用 setTimeout 确保 DOM 已稳定
    setTimeout(() => {
      let container = document.getElementById(containerId)

      // 如果容器不存在，自动创建（解决 v-for 不渲染的问题）
      if (!container && options.playVideoContainer) {
        container = document.createElement('div')
        container.id = containerId
        container.className = 'call-video-player'
        options.playVideoContainer.appendChild(container)
      }

      if (container && userInfo.videoTrack) {
        userInfo.videoTrack.play(container)
      }
    }, 100)
  }

  /**
   * 获取所有远端用户 UID
   */
  function getRemoteUserIds(): number[] {
    return Array.from(remoteUsers.value.keys())
  }

  /**
   * 检查是否有远端用户
   */
  function hasRemoteUsers(): boolean {
    return remoteUsers.value.size > 0
  }

  // 组件卸载时自动清理
  onBeforeUnmount(() => {
    cleanup()
  })

  return {
    // 状态
    isConnected,
    isMicMuted,
    remoteUsers,
    currentCredentials,
    isSecureContext,

    // 方法
    initClient,
    cleanup,
    toggleMic,
    toggleRemoteMute,
    playRemoteVideo,
    getRemoteUserIds,
    hasRemoteUsers,
  }
}

export type UseAgoraRtcReturn = ReturnType<typeof useAgoraRtc>