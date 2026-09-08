<template>
  <div class="app-container">
    <ModuleHeader compact module="live" />
    <div class="monitor-header">
      <div class="header-right">
        <el-select
          v-model="splitType"
          class="split-select"
          placeholder="分屏选择"
          @change="handleSplitChange"
        >
          <el-option label="1分屏" :value="1" />
          <el-option label="4分屏" :value="4" />
          <el-option label="9分屏" :value="9" />
          <el-option label="16分屏" :value="16" />
          <el-option label="25分屏" :value="25" />
        </el-select>
        <el-button
          v-if="splitType > 1"
          class="add-btn"
          icon="Plus"
          type="primary"
          @click="handleAdd"
        >
          添加监控
        </el-button>
      </div>
    </div>

    <div class="monitor-grid-container" :class="'grid-' + splitType">
      <div
        v-for="(item, index) in splitType"
        :key="index"
        class="monitor-item"
        :class="{ 'has-monitor': !!monitoringList[index] }"
        :data-monitor-index="index"
      >
        <!-- 有监控数据时显示视频 -->
        <template v-if="monitoringList[index]">
          <div class="monitor-surface">
            <!-- 通话模式显示音视频 -->
            <template v-if="monitoringList[index].isCallMode">
              <div class="video-container call-video-container">
                <!-- 远端视频区域 - 固定容器，由 playRemoteVideo 动态创建子元素 -->
                <div class="call-video-player" :id="`call-player-${index}`">
                  <div v-if="!hasRemoteVideo(index)" class="call-video-placeholder">
                    <el-icon class="camera-icon call-icon"><Phone /></el-icon>
                    <span class="placeholder-text">等待对方开启视频</span>
                  </div>
                </div>

                <!-- 连接中显示 -->
                <div v-if="!isCallConnected(index)" class="call-connecting">
                  <el-icon class="call-icon is-rotating"><Loading /></el-icon>
                  <span>正在连接...</span>
                </div>
              </div>
            </template>
            <!-- 有视频地址时显示播放器 -->
            <template v-else-if="monitoringList[index].videoUrl">
              <div class="video-container">
                <video
                  class="video-player"
                  muted
                  playsinline
                  webkit-playsinline
                ></video>
                <!-- 视频状态指示器 -->
                <div
                  class="video-status-indicator"
                  :class="videoStatusMap.get(index)"
                >
                  <span v-if="videoStatusMap.get(index) === 'connecting'"
                    >连接中...</span
                  >
                  <span v-else-if="videoStatusMap.get(index) === 'reconnecting'"
                    >重连中...</span
                  >
                  <span v-else-if="videoStatusMap.get(index) === 'error'"
                    >连接失败</span
                  >
                </div>
              </div>
            </template>
            <!-- 无视频地址时显示占位符 -->
            <template v-else>
              <div class="video-placeholder">
                <BrandedEmpty compact description="暂无视频流" device />
              </div>
            </template>

            <div class="monitor-tags">
              <!-- 非通话模式显示在线状态 -->
              <template v-if="!monitoringList[index].isCallMode">
                <div
                  class="monitor-tag monitor-tag-status"
                  :class="getMonitorStatusClass(monitoringList[index])"
                >
                  {{ getMonitorStatusLabel(monitoringList[index]) }}
                </div>
              </template>
              <div class="monitor-tag monitor-tag-device">
                {{ monitoringList[index].deviceNo }}
              </div>
              <div class="monitor-tag monitor-tag-user">
                {{ monitoringList[index].userName }}
              </div>
              <!-- 通话模式不显示通话中标签 -->
              <!-- 普通模式显示呼叫按钮 -->
              <template v-if="!monitoringList[index].isCallMode">
                <div
                  class="monitor-tag monitor-tag-call"
                  @click.stop="handleCallMonitor(monitoringList[index])"
                >
                  <el-icon><Microphone /></el-icon>
                  <span>呼叫</span>
                </div>
              </template>
              <!-- 通话模式显示挂断按钮 -->
              <template v-if="monitoringList[index].isCallMode">
                <div
                  class="monitor-tag monitor-tag-hangup"
                  @click.stop="hangupCall(index)"
                >
                  <el-icon><Phone /></el-icon>
                </div>
              </template>
              <!-- 普通模式显示关闭按钮 -->
              <template v-else>
                <div
                  class="monitor-tag monitor-tag-close"
                  @click.stop="removeMonitor(index)"
                >
                  <el-icon><Close /></el-icon>
                </div>
              </template>
            </div>
          </div>
        </template>
        <!-- 无监控数据时显示占位符 -->
        <template v-else>
          <button class="video-placeholder video-placeholder-full" type="button" @click="handleAdd">
            <BrandedEmpty :compact="splitType > 4" description="点击添加监控" device />
          </button>
        </template>
      </div>
    </div>

    <!-- 添加监控对话框 -->
    <el-dialog
      v-model="open"
      append-to-body
      class="custom-dialog monitoring-dialog"
      title="添加监控"
      width="1000px"
    >
      <el-form
        ref="queryRef"
        class="search-form-mini"
        :inline="true"
        :model="queryParams"
      >
        <el-form-item label="安全帽编号：" prop="hatNumber">
          <el-input
            v-model="queryParams.hatNumber"
            class="w-150"
            clearable
            placeholder="请输入"
          />
        </el-form-item>
        <el-form-item label="人员姓名：" prop="bindUserName">
          <el-input
            v-model="queryParams.bindUserName"
            class="w-150"
            clearable
            placeholder="请输入"
          />
        </el-form-item>
        <el-form-item>
          <el-button
            class="search-btn"
            icon="Search"
            type="primary"
            @click="handleQuery"
            >搜索</el-button
          >
          <el-button class="reset-btn" icon="Refresh" @click="resetQuery"
            >清空</el-button
          >
        </el-form-item>
      </el-form>

      <el-table
        v-loading="loading"
        class="custom-table"
        :data="helmetList"
      >
      <template #empty><BrandedEmpty compact description="暂无记录" /></template>
        <el-table-column align="center" label="序号" type="index" width="60" />
        <el-table-column align="center" label="安全帽编号" prop="hatNumber" />
        <el-table-column align="center" label="所属群组" prop="bindGroup" />
        <el-table-column align="center" label="绑定人员" prop="bindUserName" />
        <el-table-column align="center" label="操作" width="100">
          <template #default="scope">
            <template v-if="isAlreadyInMonitor(scope.row)">
              <el-button
                disabled
                size="small"
                type="info"
              >已添加</el-button>
            </template>
            <template v-else-if="isSelected(scope.row)">
              <el-button
                plain
                size="small"
                type="success"
                @click="cancelSelect(scope.row)"
              >已选择</el-button>
            </template>
            <template v-else>
              <el-button
                :class="{ 'limit-disabled-btn': isSelectionLimitReached }"
                :disabled="isSelectionLimitReached"
                size="small"
                type="primary"
                @click="selectHelmet(scope.row)"
              >选择</el-button>
            </template>
          </template>
        </el-table-column>
      </el-table>

      <div class="pg-container">
        <pagination
          v-show="total > 0"
          v-model:limit="queryParams.size"
          v-model:page="queryParams.current"
          :total="total"
          @pagination="getList"
        />
      </div>

      <template #footer>
        <div class="dialog-footer">
          <el-button @click="open = false">取消</el-button>
          <el-button
            :disabled="selectedHelmets.length === 0"
            type="primary"
            @click="confirmAddMonitors"
          >确定添加 ({{ selectedHelmets.length }})</el-button>
        </div>
      </template>
    </el-dialog>

    <!-- 视频详情对话框 -->
    <el-dialog
      v-model="openVideo"
      append-to-body
      class="video-dialog"
      :show-close="true"
      :title="currentVideo?.deviceNo || '视频详情'"
      width="1200px"
      @close="onVideoDialogClose"
      @open="onVideoDialogOpen"
    >
      <div class="video-wrapper">
        <div class="video-detail-container">
          <!-- 有视频地址时播放 -->
          <template v-if="currentVideo?.videoUrl">
            <video
              ref="detailVideoRef"
              autoplay
              class="detail-video-player"
              controls
              muted
              playsinline
              webkit-playsinline
            ></video>
          </template>
          <!-- 无视频地址时显示占位 -->
          <template v-else>
            <div class="video-placeholder-large">
              <el-icon class="camera-icon-large"><VideoCamera /></el-icon>
              <span class="placeholder-text-large">暂无视频流</span>
            </div>
          </template>
        </div>

        <!-- 设备信息面板 -->
        <div v-if="currentVideo" class="video-info-panel">
          <div class="info-item">
            <span class="info-label">设备编号：</span>
            <span class="info-value">{{ currentVideo.deviceNo }}</span>
          </div>
          <div class="info-item">
            <span class="info-label">人员姓名：</span>
            <span class="info-value">{{ currentVideo.userName }}</span>
          </div>
          <div class="info-item">
            <span class="info-label">所属群组：</span>
            <span class="info-value">{{ currentVideo.group }}</span>
          </div>
          <div class="info-item">
            <span class="info-label">设备状态：</span>
            <span class="status-tag">{{
              currentVideo.status === "online" ? "在线" : "离线"
            }}</span>
          </div>
        </div>
      </div>
    </el-dialog>

    <!-- 音视频通话弹窗 -->
    <AgoraVideoDialog
      v-model="openAgoraVideo"
      :title="agoraVideoTitle"
      :credentials="agoraCredentials"
      :is-playback="false"
      @hangup="handleAgoraHangup"
      @credentials-clear="agoraCredentials = null"
    />
  </div>
</template>

<script setup name="Live">
import {
  VideoCamera,
  Close,
  Microphone,
  Phone,
  Loading,
  SwitchButton,
} from "@element-plus/icons-vue";
import { hatSafetyInfoPage } from "@/api/helmet";
import { createSingleCall, endIntercom } from "@/api/intercom";
import FlvExtend from "flv-extend";
import { computed, getCurrentInstance, nextTick, onBeforeUnmount, reactive, ref, watch } from "vue";
import AgoraVideoDialog from "@/components/AgoraVideoDialog/index.vue";
import { useAgoraRtc } from "@/hooks/useAgoraRtc";

const { proxy } = getCurrentInstance();

const splitType = ref(1);
const open = ref(false);
const openVideo = ref(false);
const loading = ref(false);
const total = ref(0);

// 音视频通话相关
const openAgoraVideo = ref(false);
const agoraVideoTitle = ref("呼叫详情");
const agoraCredentials = ref(null);
const currentCallRecordId = ref(null);
const currentCallDevice = ref(null);

// 存储播放器实例的Map: key为监控项索引, value为{flvInstance, player, status}
const playerMap = new Map();

// 视频流状态监控
const videoStatusMap = ref(new Map()); // 存储每个监控的视频状态

const queryParams = reactive({
  current: 1,
  size: 10,
  hatNumber: "",
  bindUserName: "",
});

const monitoringList = ref([]);

const helmetList = ref([]);

// 已选择的安全帽列表（用于批量添加）
const selectedHelmets = ref([]);

// 存储每个通话卡片的 Agora 实例: key为监控索引, value为useAgoraRtc返回的对象
const callAgoraClients = ref(new Map());

// 存储每个卡片的 remoteUsers watch 停止函数
const callRemoteUsersWatch = new Map();

// 存储每个通话卡片的连接状态: key为监控索引, value为boolean
const callConnectionStatus = ref(new Map());

// 正在呼叫中的设备ID集合
const callingDevices = ref(new Set());

// 通话中的设备ID -> 监控索引映射
const callDeviceIndexMap = ref(new Map());

const isSelectionLimitReached = computed(() => {
  return monitoringList.value.length + selectedHelmets.value.length >= splitType.value;
});

// 检查设备是否正在呼叫中
function isCalling(row) {
  return callingDevices.value.has(row.id);
}

// 检查设备是否已在通话中（已添加到监控列表的通话模式卡片）
function isInCall(row) {
  return monitoringList.value.some(item => item.isCallMode && item.id === row.id);
}

// 当前选中的视频（用于弹窗播放）
const currentVideo = ref(null);

// 详情弹窗视频元素引用
const detailVideoRef = ref(null);

// 详情弹窗播放器实例
let detailPlayer = null;
let detailFlvInstance = null;

// 检查安全帽是否已被选中
function isSelected(row) {
  return selectedHelmets.value.some((item) => item.id === row.id);
}

// 检查设备是否已经在监控列表中
function isAlreadyInMonitor(row) {
  return monitoringList.value.some((item) => item.id === row.id);
}

// 选择安全帽
function selectHelmet(row) {
  if (isSelectionLimitReached.value) {
    proxy.$modal.msgWarning("已达到分屏上限，请先移除部分监控");
    return;
  }
  if (!isSelected(row)) {
    selectedHelmets.value.push(row);
  }
}

// 取消选择
function cancelSelect(row) {
  const index = selectedHelmets.value.findIndex((item) => item.id === row.id);
  if (index !== -1) {
    selectedHelmets.value.splice(index, 1);
  }
}

/** 确定添加监控并发起呼叫 */
async function confirmAddMonitors() {
  console.log("[调试] confirmAddMonitors 被调用, selectedHelmets:", selectedHelmets.value);

  if (selectedHelmets.value.length === 0) {
    proxy.$modal.msgWarning("请至少选择一个设备");
    return;
  }

  // 检查分屏数是否足够
  const availableSlots = splitType.value - monitoringList.value.length;
  if (selectedHelmets.value.length > availableSlots) {
    proxy.$modal.msgWarning(`当前分屏数为 ${splitType.value}，最多还能添加 ${availableSlots} 个设备，请先切换分屏`);
    return;
  }

  // 关闭对话框
  open.value = false;
  console.log("[调试] 开始逐个呼叫, 数量:", selectedHelmets.value.length);

  // 逐个呼叫选中的设备
  for (const helmet of selectedHelmets.value) {
    console.log("[调试] 正在呼叫:", helmet.hatNumber);
    await callAndAddHelmet(helmet);
  }

  // 清空选择列表
  selectedHelmets.value = [];
  console.log("[调试] 呼叫流程完成");
}

/** 呼叫单个设备并添加到监控列表 */
async function callAndAddHelmet(row) {
  console.log("[调试] callAndAddHelmet 开始, hatNumber:", row.hatNumber);

  if (monitoringList.value.length >= splitType.value) {
    console.log("[调试] 监控列表已满，跳过");
    proxy.$modal.msgWarning(`监控列表已满，跳过设备 ${row.hatNumber}`);
    return;
  }

  // 标记为呼叫中
  callingDevices.value.add(row.id);

  try {
    console.log("[调试] 调用 createSingleCall...");
    const res = await createSingleCall({
      hatNumber: row.hatNumber,
      participant: row.bindUserName
    });

    console.log("[调试] API 返回:", res);

    if (res.code === 200) {
      const callRecordId = res.data?.id;

      // 提取声网凭证
      const responseData = res.data?.data || res.data;
      const credentials = {
        agoraAppId: responseData?.agoraAppId || responseData?.appId,
        channelName: responseData?.channelName || responseData?.channel,
        agoraUid: responseData?.agoraUid || responseData?.uid,
        agoraToken: responseData?.agoraToken || responseData?.token
      };

      console.log("[调试] 凭证:", credentials);

      if (credentials.agoraAppId) {
        // 添加到监控列表
        const newIndex = monitoringList.value.length;

        monitoringList.value.push({
          id: row.id,
          deviceNo: row.hatNumber,
          userName: row.bindUserName || row.userName || "未知",
          group: row.bindGroup || "未分组",
          status: "online",
          videoUrl: null,
          isCallMode: true,
          callRecordId: callRecordId,
          credentials: credentials
        });

        // 强制触发响应式更新
        monitoringList.value = [...monitoringList.value];

        console.log("[调试] monitoringList 更新后:", monitoringList.value);
        console.log("[调试] monitoringList[", newIndex, "]:", monitoringList.value[newIndex]);

        // 记录设备ID到索引的映射
        callDeviceIndexMap.value.set(row.id, newIndex);

        callingDevices.value.delete(row.id);

        proxy.$modal.msgSuccess(`${row.bindUserName || row.hatNumber} 已添加`);
        console.log("[调试] 卡片添加成功，当前数量:", monitoringList.value.length);

        // 等待 DOM 更新后再初始化 Agora
        await nextTick();

        // 初始化该卡片的 Agora 连接（失败不影响卡片显示）
        try {
          await initCallAgoraClient(newIndex, credentials);
        } catch (agoraError) {
          console.error("[调试] Agora 初始化失败:", agoraError);
          // Agora 初始化失败不影响卡片显示，只记录错误
        }
      } else {
        callingDevices.value.delete(row.id);
        proxy.$modal.msgWarning("未获取到音视频凭证");
      }
    } else {
      callingDevices.value.delete(row.id);
      proxy.$modal.msgError(`呼叫失败: ${res.msg}`);
    }
  } catch (error) {
    callingDevices.value.delete(row.id);
    console.error("[调试] 呼叫异常:", error);
    proxy.$modal.msgError("呼叫失败");
  }
}

/** 初始化通话卡片的 Agora 客户端 */
async function initCallAgoraClient(index, credentials) {
  try {
    // 获取该卡片的视频容器父元素
    const monitorItem = document.querySelector(`.monitor-item[data-monitor-index="${index}"]`)
    const videoContainer = monitorItem?.querySelector('.call-video-container') || null

    // 创建独立的 Agora 实例（卡片只查看，不请求麦克风权限）
    const agoraClient = useAgoraRtc({
      enableLocalAudio: false,
      playVideoContainer: videoContainer || null,
      onConnected: () => {
        console.log(`[Agora] 卡片 ${index} 连接成功`);
        // 更新连接状态
        callConnectionStatus.value.set(index, true);
        callConnectionStatus.value = new Map(callConnectionStatus.value);
        // 连接成功后，兜底播放已有的远端用户视频
        // playRemoteVideo 内部有 setTimeout，这里直接调用即可
        const client = callAgoraClients.value.get(index);
        if (client && client.remoteUsers?.value) {
          client.remoteUsers.value.forEach((userInfo, uid) => {
            if (userInfo.hasVideo && userInfo.videoTrack) {
              client.playRemoteVideo(uid, `call-player-${index}`);
            }
          });
        }
      },
      onError: (error) => {
        console.error(`[Agora] 卡片 ${index} 连接失败:`, error);
        // 更新连接状态
        callConnectionStatus.value.set(index, false);
        callConnectionStatus.value = new Map(callConnectionStatus.value);
        proxy.$modal.msgError(`通话连接失败: ${error.message}`);
      },
      onUserJoined: (uid) => {
        console.log(`[Agora] 卡片 ${index} 用户加入:`, uid);
        // playRemoteVideo 内部有 setTimeout，这里直接调用即可
        const client = callAgoraClients.value.get(index);
        if (client) {
          client.playRemoteVideo(uid, `call-player-${index}`);
        }
      },
      onUserLeft: (uid) => {
        console.log(`[Agora] 卡片 ${index} 用户离开:`, uid);
      }
    });

    // 存储客户端实例
    callAgoraClients.value.set(index, agoraClient);
    // 初始状态为未连接
    callConnectionStatus.value.set(index, false);
    callConnectionStatus.value = new Map(callConnectionStatus.value);

    // 监听远端用户变化，自动播放视频（类似 AgoraVideoDialog）
    const stopWatch = watch(agoraClient.remoteUsers, (newMap) => {
      newMap.forEach((userInfo, uid) => {
        if (userInfo.hasVideo && userInfo.videoTrack) {
          // playRemoteVideo 内部有 setTimeout，这里直接调用即可
          agoraClient.playRemoteVideo(uid, `call-player-${index}`)
        }
      })
    })
    callRemoteUsersWatch.set(index, stopWatch);

    // 初始化连接
    const success = await agoraClient.initClient(credentials);
    if (!success) {
      proxy.$modal.msgError(`卡片 ${index + 1} 音视频连接失败`);
      callConnectionStatus.value.set(index, false);
      callConnectionStatus.value = new Map(callConnectionStatus.value);
    }
  } catch (error) {
    console.error(`[Agora] 初始化卡片 ${index} 失败:`, error);
    proxy.$modal.msgError(`卡片 ${index + 1} 初始化失败: ${error.message}`);
    callConnectionStatus.value.set(index, false);
    callConnectionStatus.value = new Map(callConnectionStatus.value);
  }
}

/** 获取指定索引卡片的远端用户列表 */
function getCallRemoteUsers(index) {
  const client = callAgoraClients.value.get(index);
  if (!client || !client.remoteUsers || !client.remoteUsers.value) return [];
  return Array.from(client.remoteUsers.value.entries());
}

/** 检查指定索引卡片是否有远端视频 */
function hasRemoteVideo(index) {
  const client = callAgoraClients.value.get(index);
  if (!client || !client.remoteUsers || !client.remoteUsers.value) return false;
  for (const userInfo of client.remoteUsers.value.values()) {
    if (userInfo.hasVideo) return true;
  }
  return false;
}

/** 检查指定索引卡片是否已连接 */
function isCallConnected(index) {
  return callConnectionStatus.value.get(index) || false;
}

/** 检查指定索引卡片的麦克风是否静音 */
function isCallMicMuted(index) {
  const client = callAgoraClients.value.get(index);
  return client ? client.isMicMuted.value : false;
}

/** 挂断指定索引卡片的通话 */
async function hangupCall(index) {
  const client = callAgoraClients.value.get(index);
  const item = monitoringList.value[index];

  // 停止 watch
  const stopWatch = callRemoteUsersWatch.get(index);
  if (stopWatch) {
    stopWatch();
    callRemoteUsersWatch.delete(index);
  }

  if (client) {
    await client.cleanup();
    callAgoraClients.value.delete(index);
  }

  // 结束对讲记录
  if (item?.callRecordId) {
    await endIntercom({ id: item.callRecordId });
  }

  // 移除监控项
  removeMonitor(index);
}

/** 切换指定索引卡片的麦克风 */
function toggleCallMic(index) {
  const client = callAgoraClients.value.get(index);
  if (client) {
    client.toggleMic();
  }
}

/** 清理指定索引的 Agora 客户端 */
function cleanupCallAgoraClient(index) {
  // 停止 watch
  const stopWatch = callRemoteUsersWatch.get(index);
  if (stopWatch) {
    stopWatch();
    callRemoteUsersWatch.delete(index);
  }

  const client = callAgoraClients.value.get(index);
  if (client) {
    client.cleanup();
    callAgoraClients.value.delete(index);
  }
  // 清理连接状态
  callConnectionStatus.value.delete(index);
  callConnectionStatus.value = new Map(callConnectionStatus.value);
}

/** 查询安全帽列表 */
function getList() {
  loading.value = true;
  hatSafetyInfoPage(queryParams).then((response) => {
    helmetList.value = response.data.records;
    total.value = response.data.pages * response.data.size;
    loading.value = false;
  });
}

/**
 * 初始化单个播放器的FLV播放器
 * @param {number} index - 监控项索引
 * @param {string} videoUrl - 视频流地址
 * @param {HTMLElement} videoElement - video元素
 */
function initPlayer(index, videoUrl, videoElement) {
  if (!videoElement || !videoUrl) return;

  // 如果该位置已有播放器，先销毁
  destroyPlayer(index);

  // 设置初始状态：连接中
  videoStatusMap.value.set(index, 'connecting');

  const flvInstance = new FlvExtend({
    element: videoElement,
    frameTracking: true,
    updateOnStart: true,
    updateOnFocus: true,
    reconnect: true,
    reconnectInterval: 3000, // 重连间隔 3秒
  });

  const player = flvInstance.init(
    {
      type: "flv",
      url: videoUrl,
      isLive: true,
    },
    {
      enableStashBuffer: false,
      autoCleanupSourceBuffer: true,
      stashInitialSize: 128,
      enableWorker: true,
    }
  );

  // 监听播放器事件
  player.on('error', () => {
    videoStatusMap.value.set(index, 'error');
  });

  player.on('loading_complete', () => {
    videoStatusMap.value.set(index, 'playing');
  });

  player.on('reconnect', () => {
    videoStatusMap.value.set(index, 'reconnecting');
  });

  player.play().then(() => {
    videoStatusMap.value.set(index, 'playing');
  }).catch(() => {
    videoStatusMap.value.set(index, 'error');
  });

  playerMap.set(index, {
    flvInstance,
    player,
    status: 'playing'
  });
}

/**
 * 销毁指定索引的播放器
 * @param {number} index - 监控项索引
 */
function destroyPlayer(index) {
  const playerInfo = playerMap.get(index);
  if (playerInfo) {
    try {
      if (playerInfo.player) {
        playerInfo.player.pause();
        playerInfo.player.close();
      }
      if (playerInfo.flvInstance) {
        playerInfo.flvInstance.destroy();
      }
    } catch (e) {
    }
    playerMap.delete(index);
  }
  videoStatusMap.value.delete(index);
}

/**
 * 销毁所有播放器
 */
function destroyAllPlayers() {
  playerMap.forEach((_, index) => {
    destroyPlayer(index);
  });
  playerMap.clear();
}

/**
 * 获取视频流地址（根据设备ID构建）
 * @param {string} deviceId - 设备ID
 * @returns {string|null} 视频流地址
 */
function getVideoUrl(deviceId) {
  // 优先使用环境变量配置的视频流服务器地址
  const streamServerUrl = import.meta.env.VITE_APP_STREAM_SERVER_URL;

  if (streamServerUrl) {
    // 构建完整的视频流地址
    return `${streamServerUrl}/${deviceId}.flv`;
  }

  // 开发环境 Mock 数据（仅用于测试）
  if (import.meta.env.DEV && import.meta.env.VITE_APP_MOCK_VIDEO === 'true') {
    // 返回一个公开的测试 FLV 流地址
    return 'https://sf1-hscdn-tos.pstatp.com/obj/media-fe/xgplayer_doc_video/hls/xgplayer-demo.m3u8';
  }

  // 生产环境未配置时返回 null
  return null;
}

function handleAdd() {
  selectedHelmets.value = [];
  open.value = true;
  getList();
}

function getMonitorStatusLabel(item) {
  return item?.status === "offline" ? "离线" : "在线";
}

function getMonitorStatusClass(item) {
  return item?.status === "offline" ? "offline" : "online";
}

/**
 * 打开视频详情弹窗
 * @param {Object} item - 监控项数据
 */
function openVideoDetail(item) {
  if (!item) return;
  currentVideo.value = item;
  openVideo.value = true;
}

/**
 * 详情弹窗打开时初始化播放器
 */
function onVideoDialogOpen() {
  if (!currentVideo.value?.videoUrl || !detailVideoRef.value) return;

  // 销毁之前的播放器
  onVideoDialogClose();

  nextTick(() => {
    detailFlvInstance = new FlvExtend({
      element: detailVideoRef.value,
      frameTracking: true,
      updateOnStart: true,
      updateOnFocus: true,
      reconnect: true,
      reconnectInterval: 0,
    });

    detailPlayer = detailFlvInstance.init(
      {
        type: "flv",
        url: currentVideo.value.videoUrl,
        isLive: true,
      },
      {
        enableStashBuffer: false,
        autoCleanupSourceBuffer: true,
        stashInitialSize: 128,
        enableWorker: true,
      }
    );

    detailPlayer.play();
  });
}

/**
 * 详情弹窗关闭时销毁播放器
 */
function onVideoDialogClose() {
  try {
    if (detailPlayer) {
      detailPlayer.pause();
      detailPlayer.close();
      detailPlayer = null;
    }
    if (detailFlvInstance) {
      detailFlvInstance.destroy();
      detailFlvInstance = null;
    }
  } catch (e) {
  }
}

/** 搜索按钮操作 */
function handleQuery() {
  queryParams.current = 1;
  getList();
}

/** 重置按钮操作 */
function resetQuery() {
  proxy.resetForm("queryRef");
  handleQuery();
}

/** 分屏切换处理 */
function handleSplitChange(val) {
  const oldLength = monitoringList.value.length;

  // 先清理所有通话卡片的 Agora 连接（因为索引会发生变化）
  callAgoraClients.value.forEach((client, index) => {
    client.cleanup();
    // 停止 watch
    const stopWatch = callRemoteUsersWatch.get(index);
    if (stopWatch) {
      stopWatch();
      callRemoteUsersWatch.delete(index);
    }
  });
  callAgoraClients.value.clear();
  // 清理 watch
  callRemoteUsersWatch.clear();
  // 清理连接状态
  callConnectionStatus.value.clear();
  callConnectionStatus.value = new Map();

  // 如果新的分屏数小于当前监控数量，移除多余的监控项
  if (val < oldLength) {
    // 从后往前移除
    for (let i = oldLength - 1; i >= val; i--) {
      const item = monitoringList.value[i];
      if (item) {
        // 如果是通话模式，从映射中移除
        if (item.isCallMode && item.id) {
          callDeviceIndexMap.value.delete(item.id);
          // 如果正在弹窗通话中，结束通话
          if (item.callRecordId && currentCallRecordId.value === item.callRecordId) {
            endIntercom({ id: item.callRecordId });
            if (openAgoraVideo.value) {
              openAgoraVideo.value = false;
            }
          }
        }
      }
      destroyPlayer(i);
      monitoringList.value.pop();
    }
  }

  // 更新分屏数
  splitType.value = val;

  // 等待 DOM 更新后，重新初始化所有通话卡片的 Agora 连接
  nextTick(() => {
    monitoringList.value.forEach((item, index) => {
      if (item.isCallMode && item.credentials) {
        initCallAgoraClient(index, item.credentials);
      }
    });
    // 重建设备ID到索引的映射
    rebuildCallDeviceIndexMap();
  });
}

/** 移除单个监控项 */
function removeMonitor(index) {
  const item = monitoringList.value[index];
  if (item) {
    // 如果是通话模式，从映射中移除并清理 Agora 连接
    if (item.isCallMode && item.id) {
      callDeviceIndexMap.value.delete(item.id);
      // 清理该卡片的 Agora 连接
      cleanupCallAgoraClient(index);
      // 如果正在弹窗通话中，结束通话
      if (item.callRecordId && currentCallRecordId.value === item.callRecordId) {
        endIntercom({ id: item.callRecordId });
        if (openAgoraVideo.value) {
          openAgoraVideo.value = false;
        }
      }
    }
  }
  destroyPlayer(index);
  monitoringList.value.splice(index, 1);
  shiftVideoStatusesAfterRemoval(index);
  // 优化：只移动索引变化的播放器，不销毁重建所有
  shiftPlayersAfterRemoval(index);
  // 移动 Agora 客户端映射
  shiftCallAgoraClientsAfterRemoval(index);
  // 重建设备ID到索引的映射
  rebuildCallDeviceIndexMap();
}

/** 重建设备ID到索引的映射 */
function rebuildCallDeviceIndexMap() {
  callDeviceIndexMap.value.clear();
  monitoringList.value.forEach((item, index) => {
    if (item.isCallMode && item.id) {
      callDeviceIndexMap.value.set(item.id, index);
    }
  });
}

/**
 * 删除后移动 Agora 客户端映射
 * @param {number} removedIndex - 删除的索引位置
 */
function shiftCallAgoraClientsAfterRemoval(removedIndex) {
  const clientsToShift = [];
  const watchesToShift = [];
  // 收集需要移动的客户端和 watch（从 removedIndex+1 开始）
  for (let i = removedIndex + 1; i <= monitoringList.value.length + 1; i++) {
    const client = callAgoraClients.value.get(i);
    if (client) {
      clientsToShift.push({ oldIndex: i, client });
      callAgoraClients.value.delete(i);
    }
    const stopWatch = callRemoteUsersWatch.get(i);
    if (stopWatch) {
      watchesToShift.push({ oldIndex: i, stopWatch });
      callRemoteUsersWatch.delete(i);
    }
  }
  // 重新设置到新的索引位置
  clientsToShift.forEach(({ oldIndex, client }) => {
    const newIndex = oldIndex - 1;
    callAgoraClients.value.set(newIndex, client);
  });
  watchesToShift.forEach(({ oldIndex, stopWatch }) => {
    const newIndex = oldIndex - 1;
    callRemoteUsersWatch.set(newIndex, stopWatch);
  });
}

/**
 * 优化版本：删除后只移动播放器，不重建
 * @param {number} removedIndex - 删除的索引位置
 */
function shiftPlayersAfterRemoval(removedIndex) {
  // 获取需要移动的播放器（从 removedIndex+1 开始的所有播放器）
  const playersToShift = [];
  for (let i = removedIndex + 1; i <= monitoringList.value.length; i++) {
    const playerInfo = playerMap.get(i);
    if (playerInfo) {
      playersToShift.push({ oldIndex: i, playerInfo });
    }
  }

  // 清除旧映射
  playersToShift.forEach(({ oldIndex }) => {
    playerMap.delete(oldIndex);
  });

  // 等待 DOM 更新后重新绑定播放器到新位置
  nextTick(() => {
    playersToShift.forEach(({ oldIndex, playerInfo }) => {
      const newIndex = oldIndex - 1;
      const videoElement = document.querySelector(
        `[data-monitor-index="${newIndex}"] video`
      );
      if (videoElement && videoElement !== playerInfo.flvInstance.element) {
        // 更新播放器的目标元素
        playerInfo.flvInstance.element = videoElement;
        playerMap.set(newIndex, playerInfo);
      } else if (videoElement) {
        playerMap.set(newIndex, playerInfo);
      }
    });
  });
}

function shiftVideoStatusesAfterRemoval(removedIndex) {
  const nextStatusMap = new Map();
  videoStatusMap.value.forEach((status, index) => {
    if (index < removedIndex) {
      nextStatusMap.set(index, status);
    } else if (index > removedIndex) {
      nextStatusMap.set(index - 1, status);
    }
  });
  videoStatusMap.value = nextStatusMap;
}

/**
 * 呼叫监控设备（发起音视频通话）
 * 如果设备已在卡片中且有凭证，直接打开弹窗
 */
function handleCallMonitor(item) {
  if (!item) return;

  // 如果设备已经有通话凭证（通过添加监控流程添加的），直接打开弹窗
  if (item.isCallMode && item.credentials) {
    currentCallDevice.value = item;
    currentCallRecordId.value = item.callRecordId;
    agoraVideoTitle.value = `呼叫 ${item.userName}`;
    agoraCredentials.value = item.credentials;
    openAgoraVideo.value = true;
    return;
  }

  // 否则发起新的呼叫
  currentCallDevice.value = item;

  createSingleCall({
    hatNumber: item.deviceNo,
    participant: item.userName
  }).then(res => {
    if (res.code === 200) {
      currentCallRecordId.value = res.data?.id;
      agoraVideoTitle.value = `呼叫 ${item.userName}`;

      // 提取声网凭证
      const responseData = res.data?.data || res.data;
      const credentials = {
        agoraAppId: responseData?.agoraAppId || responseData?.appId,
        channelName: responseData?.channelName || responseData?.channel,
        agoraUid: responseData?.agoraUid || responseData?.uid,
        agoraToken: responseData?.agoraToken || responseData?.token
      };

      if (credentials.agoraAppId) {
        agoraCredentials.value = credentials;
        openAgoraVideo.value = true;
      } else {
        proxy.$modal.msgWarning('未获取到音视频凭证，仅创建了对讲记录');
      }
    }
  });
}

/**
 * 音视频通话挂断处理
 * 如果是卡片通话模式，挂断时只关闭弹窗，不移除卡片
 */
function handleAgoraHangup() {
  // 只有非卡片模式的通话才需要结束对讲
  if (currentCallDevice.value && !currentCallDevice.value.isCallMode && currentCallRecordId.value) {
    endIntercom({ id: currentCallRecordId.value }).then(() => {
      proxy.$modal.msgSuccess('已结束通话');
    });
  }
  agoraCredentials.value = null;
  currentCallRecordId.value = null;
  currentCallDevice.value = null;
}

// 组件卸载时销毁所有播放器
onBeforeUnmount(() => {
  destroyAllPlayers();
  // 清理所有通话卡片的 Agora 连接
  callAgoraClients.value.forEach((client, index) => {
    client.cleanup();
    // 停止 watch
    const stopWatch = callRemoteUsersWatch.get(index);
    if (stopWatch) {
      stopWatch();
    }
  });
  callAgoraClients.value.clear();
  callRemoteUsersWatch.clear();
  // 清理连接状态
  callConnectionStatus.value.clear();
  callConnectionStatus.value = new Map();
});
</script>

<style scoped lang="scss">
@import "@/assets/styles/variables.module.scss";

@keyframes fadeIn {
  from {
    opacity: 0;
    transform: scale(0.95);
  }
  to {
    opacity: 1;
    transform: scale(1);
  }
}

.app-container {
  padding: 8px var(--section-padding) var(--section-padding);
  height: calc(100vh - 60px);
  overflow: hidden;
  display: flex;
  flex-direction: column;
}

.monitor-header {
  display: flex;
  justify-content: flex-end;
  align-items: center;
  // Tight padding for header - it's a single row
  padding: var(--space-3) 0;
  // Generous margin-bottom creates separation from content
  margin-bottom: var(--space-4);

  .title {
    font-size: var(--text-xl);
    font-weight: var(--font-bold);
    color: var(--text-primary);
  }
}

.header-right {
  display: flex;
  // Tight grouping for related controls
  gap: var(--gap-tight);

  .split-select {
    width: 120px;
    :deep(.el-input__wrapper) {
      height: 36px;
      box-sizing: border-box;
    }
    :deep(.el-input__inner) {
      font-weight: var(--font-medium);
      height: 36px;
    }
  }

  .add-btn {
    background-color: var(--color-primary);
    border-color: var(--color-primary);
    font-weight: var(--font-semibold);
    height: 36px;
    display: flex;
    align-items: center;
    &:hover {
      background-color: var(--color-primary-hover);
      border-color: var(--color-primary-hover);
    }
  }
}

.monitor-grid-container {
  flex: 1;
  padding: 0;
  display: grid;
  // Consistent gap regardless of grid density
  gap: var(--gap-relaxed);
  overflow: hidden;
  transition: all 0.3s ease-in-out;

  &.grid-1 {
    grid-template-columns: 1fr;
    grid-template-rows: 1fr;
  }
  &.grid-4 {
    grid-template-columns: repeat(2, 1fr);
    grid-template-rows: repeat(2, 1fr);
  }
  &.grid-9 {
    grid-template-columns: repeat(3, 1fr);
    grid-template-rows: repeat(3, 1fr);
    // Slightly tighter for 9-up, but still consistent
    gap: var(--space-3);
  }
  &.grid-16 {
    grid-template-columns: repeat(4, 1fr);
    grid-template-rows: repeat(4, 1fr);
    gap: var(--space-3);
  }
  &.grid-25 {
    grid-template-columns: repeat(5, 1fr);
    grid-template-rows: repeat(5, 1fr);
    gap: var(--space-2);
  }
}

.monitor-item {
  min-height: 0;
  position: relative;
  transition: all 0.3s ease-in-out;
  animation: fadeIn 0.3s ease-in-out;

  &.has-monitor {
    cursor: pointer;
  }
}

.monitor-surface {
  position: relative;
  width: 100%;
  height: 100%;
  overflow: hidden;
  border-radius: 10px;
  isolation: isolate;
  background: #151c26;
  border: 1px solid var(--border-color);
  box-shadow: var(--shadow-sm);
  transition: border-color 0.24s ease, box-shadow 0.24s ease;

  &::after {
    content: "";
    position: absolute;
    inset: 0;
    background: rgba(8, 13, 20, 0.08);
    z-index: 0;
    pointer-events: none;
  }
}

.monitor-surface > .video-container,
.monitor-surface > .video-placeholder {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  border-radius: inherit;
}

.monitor-surface .video-container {
  display: flex;
  align-items: center;
  justify-content: center;
  background: #0f172a;
  overflow: hidden;

  .video-player {
    width: 100%;
    height: 100%;
    object-fit: cover;
    background: #020617;
  }

  .video-status-indicator {
    position: absolute;
    // Tight inset for status badge
    top: var(--space-3);
    left: var(--space-3);
    padding: var(--space-1) var(--space-3);
    border-radius: 999px;
    font-size: var(--text-xs);
    font-weight: var(--font-semibold);
    letter-spacing: var(--tracking-wide);
    z-index: 4;
    opacity: 0;
    transition: opacity 0.24s ease;
    backdrop-filter: blur(10px);
    border: 1px solid rgba(255, 255, 255, 0.14);

    &.connecting,
    &.reconnecting {
      background: rgba(37, 99, 235, 0.78);
      color: #eff6ff;
      opacity: 1;
    }

    &.error {
      background: rgba(220, 38, 38, 0.82);
      color: #fff5f5;
      opacity: 1;
    }
  }
}

.video-placeholder {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  min-height: 0;
  background: var(--bg-soft);
  transition: background-color 0.3s ease, transform 0.24s ease;
  position: relative;

  &.video-placeholder-full {
    width: 100%;
    height: 100%;
    font: inherit;
    color: var(--text-secondary);
    background: var(--bg-soft);
    border-radius: 10px;
    border: 1px dashed var(--border-hover);
    box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.02);
    cursor: pointer;

    &:hover,
    &:focus-visible {
      background: var(--bg-selected);
      border-color: var(--color-primary);
    }
  }

  // 通话模式占位符样式
  &.call-mode-placeholder {
    cursor: default;
    background: #15243a;
    border: 1px solid rgba(59, 130, 246, 0.3);

    .call-icon {
      color: #60a5fa;
      animation: pulse 2s infinite;
    }

    .call-status {
      color: #93c5fd;
      font-size: clamp(10px, 0.8vw, 12px);
      margin-top: 8px;
      opacity: 0.8;
    }
  }

  @keyframes pulse {
    0%, 100% {
      opacity: 1;
      transform: scale(1);
    }
    50% {
      opacity: 0.7;
      transform: scale(1.1);
    }
  }

  .camera-icon {
    font-size: clamp(24px, 5vw, 80px);
    color: #fff;
    opacity: 0.82;
    margin-bottom: 12px;
  }

  .placeholder-text {
    color: #cbd5e1;
    font-size: clamp(12px, 1vw, 14px);
    letter-spacing: 0.02em;
  }
}

.monitor-tags {
  position: absolute;
  top: var(--space-3);
  right: var(--space-3);
  z-index: 50; // 提高层级，确保在通话内容之上
  display: flex;
  flex-wrap: wrap;
  justify-content: flex-end;
  // Tight grouping for tag cluster
  gap: var(--gap-tight);
}

.monitor-tag {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 0;
  max-width: 160px;
  // Consistent padding using scale
  padding: 0 var(--space-3);
  height: 28px;
  border-radius: 6px;
  font-size: var(--text-xs);
  font-weight: var(--font-bold);
  letter-spacing: var(--tracking-wide);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  border: 1px solid rgba(255, 255, 255, 0.12);
  backdrop-filter: blur(8px);
  box-shadow: 0 3px 10px rgba(0, 0, 0, 0.22);
}

.monitor-tag-status {
  &.online {
    background: rgba(20, 83, 45, 0.82);
    border-color: rgba(74, 222, 128, 0.38);
    color: #dcfce7;
  }

  &.offline {
    background: rgba(127, 29, 29, 0.82);
    border-color: rgba(248, 113, 113, 0.38);
    color: #fee2e2;
  }
}

.monitor-tag-device {
  background: rgba(15, 23, 42, 0.78);
  color: #f8fafc;
}

.monitor-tag-user {
  background: rgba(30, 41, 59, 0.72);
  color: #dbeafe;
}

.monitor-tag-call {
  background: rgba(59, 130, 246, 0.82);
  border-color: rgba(96, 165, 250, 0.38);
  color: #eff6ff;
  cursor: pointer;
  display: flex;
  align-items: center;
  gap: 4px;

  &:hover {
    background: rgba(96, 165, 250, 0.92);
    transform: translateY(-1px);
  }

  .el-icon {
    font-size: 14px;
  }
}

// 通话模式视频容器样式
.call-video-container {
  position: relative;
  width: 100%;
  height: 100%;
  background: #0f172a;
  display: flex;
  flex-direction: column;

  .call-video-player {
    flex: 1;
    position: relative;
    min-height: 0;
    width: 100%;
    height: 100%;

    > div {
      width: 100% !important;
      height: 100% !important;
    }

    video {
      width: 100%;
      height: 100%;
      object-fit: cover;
    }
  }

  .call-video-placeholder {
    position: absolute;
    inset: 0;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    background: #15243a;

    .call-icon {
      font-size: clamp(24px, 4vw, 48px);
      color: #60a5fa;
    }

    .placeholder-text {
      margin-top: 8px;
      color: #93c5fd;
      font-size: clamp(10px, 0.9vw, 14px);
    }
  }

  .call-connecting {
    position: absolute;
    top: 50%;
    left: 50%;
    transform: translate(-50%, -50%);
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    padding: 24px 32px;
    background: rgba(15, 23, 42, 0.85);
    border-radius: 12px;
    z-index: 10;

    .call-icon {
      font-size: clamp(24px, 4vw, 48px);
      color: #60a5fa;
      margin-bottom: 8px;

      &.is-rotating {
        animation: rotating 2s linear infinite;
      }
    }

    span {
      color: #93c5fd;
      font-size: clamp(10px, 0.9vw, 14px);
    }
  }

  .call-controls {
    position: absolute;
    bottom: 8px;
    left: 50%;
    transform: translateX(-50%);
    display: flex;
    gap: 8px;
    padding: 8px 12px;
    background: rgba(15, 23, 42, 0.8);
    border-radius: 20px;
    z-index: 20;

    .el-button {
      font-size: 12px;
      height: 28px;
      padding: 0 12px;

      .el-icon {
        font-size: 14px;
        margin-right: 4px;
      }
    }
  }
}

@keyframes rotating {
  from {
    transform: rotate(0deg);
  }
  to {
    transform: rotate(360deg);
  }
}

.monitor-tag-close {
  width: 28px;
  min-width: 28px;
  height: 28px;
  padding: 0;
  background: rgba(220, 38, 38, 0.72);
  color: #f8fafc;
  border-radius: 50%;
  transition: background-color 0.2s ease;

  .el-icon {
    font-size: 14px;
  }
}

.monitor-tag-close:hover {
  background: rgba(220, 38, 38, 0.92);
}

.monitor-tag-hangup {
  width: 28px;
  min-width: 28px;
  height: 28px;
  padding: 0;
  background: rgba(220, 38, 38, 0.72);
  color: #f8fafc;
  border-radius: 50%;

  .el-icon {
    font-size: 14px;
  }

  &:hover {
    background: rgba(220, 38, 38, 0.92);
  }
}

.monitor-grid-container.grid-16,
.monitor-grid-container.grid-25 {
  .monitor-surface,
  .video-placeholder.video-placeholder-full {
    border-radius: 8px;
  }

  .monitor-tags {
    // Slightly tighter for dense grids, but still from scale
    top: var(--space-2);
    right: var(--space-2);
    gap: 6px;
  }

  .monitor-tag {
    height: 24px;
    padding: 0 var(--space-2);
    font-size: var(--text-xs);
    max-width: 128px;
  }

  .video-status-indicator {
    top: var(--space-2);
    left: var(--space-2);
    padding: var(--space-1) var(--space-2);
    font-size: var(--text-xs);
  }

  .monitor-tag-close {
    width: 24px;
    min-width: 24px;

    .el-icon {
      font-size: var(--text-xs);
    }
  }
}

.monitor-grid-container.grid-25 {
  .monitor-tags {
    max-width: calc(100% - 64px);
  }

  .monitor-tag {
    max-width: 104px;
    height: 22px;
    padding: 0 7px;
  }
}

.search-form-mini {
  // Generous separation below search form
  margin-bottom: var(--space-6);
  :deep(.el-form-item) {
    margin-bottom: 0;
  }
}

.search-btn {
  background-color: var(--color-action);
  border-color: var(--color-action);
  &:hover {
    background-color: var(--color-action-hover);
    border-color: var(--color-action-hover);
  }
}

.select-btn {
  background-color: var(--color-action);
  border-color: var(--color-action);
  &:hover {
    background-color: var(--color-action-hover);
    border-color: var(--color-action-hover);
  }
}

.limit-disabled-btn {
  &:deep(.el-button),
  &.el-button {
    &.is-disabled,
    &.is-disabled:hover,
    &.is-disabled:focus,
    &[disabled],
    &[disabled]:hover,
    &[disabled]:focus {
      background: var(--bg-muted) !important;
      border-color: var(--border-color) !important;
      color: var(--text-muted) !important;
      box-shadow: none !important;
      cursor: not-allowed !important;
    }
  }
}

.progress-val {
  font-size: var(--text-xs);
  color: var(--text-secondary);
  margin-left: var(--space-2);
}

.pg-container {
  // Generous separation above pagination
  margin-top: var(--space-6);
  display: flex;
  justify-content: flex-end;
}

.dialog-footer {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  // Tight grouping for dialog actions
  gap: var(--gap-standard);

  .selected-count {
    color: var(--text-secondary);
    font-size: var(--text-sm);
  }
}

.custom-dialog {
  :deep(.el-dialog__header) {
    // Consistent section padding
    padding: var(--space-5) var(--section-padding);
    border-bottom: 1px solid var(--border-color);
    background-color: var(--bg-pure);
    .el-dialog__title {
      font-weight: var(--font-bold);
    }
  }
  :deep(.el-dialog__body) {
    // Consistent section padding
    padding: var(--section-padding);
    background-color: var(--bg-pure);
  }
}

.status-tag {
  background-color: var(--color-success-bg) !important;
  color: var(--color-success) !important;
  border: 1px solid var(--color-success-light) !important;
  padding: 0 12px;
  height: clamp(20px, 2.5vw, 32px);
  line-height: clamp(18px, 2.3vw, 30px);
  border-radius: 16px;
  font-weight: var(--font-semibold);
  font-size: clamp(12px, 1vw, 14px);
  white-space: nowrap;
}

.video-dialog {
  :deep(.el-dialog) {
    background: transparent !important;
    box-shadow: none !important;
    border-radius: 12px;
    overflow: hidden;
    margin-top: 5vh !important;

    .el-dialog__header {
      display: block; // Show header for close button and title
      padding: 15px 24px;
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
        top: 15px;
        right: 24px;
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

// 详情弹窗样式
.video-detail-container {
  width: 100%;
  aspect-ratio: 16 / 9;
  background: #1a1a1a;
  position: relative;
  border-radius: 8px;
  overflow: hidden;

  .detail-video-player {
    width: 100%;
    height: 100%;
    object-fit: contain;
  }

  .video-placeholder-large {
    width: 100%;
    height: 100%;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    background: #2a2a2a;

    .camera-icon-large {
      font-size: var(--text-3xl);
      color: #fff;
      opacity: 0.5;
      margin-bottom: 20px;
    }

    .placeholder-text-large {
      color: var(--text-muted);
      font-size: var(--text-lg);
    }
  }
}

.video-info-panel {
  // Generous separation from video
  margin-top: var(--space-4);
  // Section padding for the panel
  padding: var(--space-4);
  background: var(--bg-soft);
  border-radius: 8px;
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  // Standard gap for info items
  gap: var(--gap-standard);

  .info-item {
    display: flex;
    align-items: center;

    .info-label {
      color: var(--text-secondary);
      font-size: var(--text-sm);
      // Tight spacing between label and value
      margin-right: var(--space-2);
    }

    .info-value {
      color: var(--text-primary);
      font-size: var(--text-sm);
      font-weight: var(--font-semibold);
    }

    .status-tag {
      background-color: var(--color-success-bg) !important;
      color: var(--color-success) !important;
      border: 1px solid var(--color-success-light) !important;
      padding: 0 var(--space-3);
      height: 28px;
      line-height: 26px;
      border-radius: 16px;
      font-weight: var(--font-semibold);
      font-size: var(--text-sm);
      white-space: nowrap;
    }
  }
}

.monitor-header { flex-shrink: 0; margin-bottom: 8px; padding-top: 0; }
.monitor-grid-container { min-height: 0; }
.monitor-item { border-radius: 12px; }
.grid-16 .branded-empty :deep(img), .grid-25 .branded-empty :deep(img) { display: none; }
</style>
