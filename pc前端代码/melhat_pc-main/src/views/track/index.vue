<template>
  <div class="app-container">
    <ModuleHeader compact module="track" />
    <el-row class="sidebar-layout" :gutter="16">
      <!-- 左侧：安全帽列表 (Col 7) -->
      <el-col class="full-height" :lg="7" :sm="24">
        <el-card class="box-card list-card" shadow="never">
          <div class="search-box">
            <el-input
              v-model="queryParams.hatIds"
              clearable
              placeholder="搜索编号"
              prefix-icon="Search"
              @input="handleQuery"
            />
          </div>

          <TableSkeleton v-if="loading && hatList.length === 0" :columns="3" :rows="5" />
          <el-table
            v-else
            v-loading="loading && hatList.length > 0"
            class="track-table"
            :data="hatList"
            height="100%"
          >
      <template #empty><BrandedEmpty compact description="暂无记录" /></template>
            <el-table-column align="center" label="编号" prop="hatNumber" />
            <el-table-column align="center" label="绑定人" prop="bindUserName" />
            <el-table-column align="center" label="操作" width="80">
              <template #default="scope">
                <el-tooltip content="轨迹回放" placement="top">
                  <el-button aria-label="轨迹回放"
                    icon="VideoPlay"
                    link
                    type="primary"
                    @click="handleTrackPlayback(scope.row)"
                  ></el-button>
                </el-tooltip>
              </template>
            </el-table-column>
          </el-table>

          <div class="pagination-wrapper">
            <pagination
              v-show="total > 0"
              v-model:limit="queryParams.size"
              v-model:page="queryParams.current"
              layout="total, sizes, prev, pager, next, jumper"
              :page-sizes="[10, 12, 20, 30, 50]"
              :total="total"
              @pagination="getList"
            />
          </div>
        </el-card>
      </el-col>

      <!-- 右侧：地图 (上) + 媒体 (下) (Col 17) -->
      <el-col class="full-height" :lg="17" :sm="24">
        <div class="right-content-area">
          <!-- 上方：地图 -->
          <div class="map-section" :class="{ 'map-full': !isPlaying }">
            <el-card class="box-card map-card" shadow="never">
              <div id="map" ref="mapContainer" class="map-view" />

              <!-- 回放控制器 -->
              <div v-if="isPlaying" class="track-controls">
                <div class="track-info">
                  <span class="status-indicator"></span>
                  回放中: {{ currentHat.bindUserName }}
                </div>
                <el-divider direction="vertical" />
                <el-button-group>
                  <el-button
                    icon="VideoPause"
                    link
                    type="primary"
                    @click="handlePause"
                  ></el-button>
                  <el-button
                    icon="VideoPlay"
                    link
                    type="primary"
                    @click="handlePlay"
                  ></el-button>
                  <el-button
                    icon="CircleClose"
                    link
                    type="danger"
                    @click="stopPlayback"
                  ></el-button>
                </el-button-group>
              </div>
            </el-card>
          </div>

          <!-- 下方：关联媒体 (回放时才显示) -->
          <div v-if="isPlaying" class="media-section">
            <el-card class="box-card media-card" shadow="never">
              <div class="section-header">
                <span class="title">轨迹点关联视频 / 图片内容</span>
              </div>
              <div class="media-content">
                <div v-if="mediaList.length === 0" class="empty-state">
                  <el-icon color="#909399" size="48"><VideoCamera /></el-icon>
                  <p>该轨迹段暂无关联媒体资源</p>
                </div>
                <div v-else class="media-grid-container">
                  <div class="media-grid">
                    <div
                      v-for="item in mediaList"
                      :key="item.id"
                      class="media-card-item"
                    >
                      <div class="media-preview">
                        <el-image 
                          v-if="isMediaImage(item.fileUrl)" 
                          fit="cover" 
                          :src="item.fileUrl" 
                          style="width: 100%; height: 100%" 
                        />
                        <div v-else class="video-placeholder">
                          <svg height="48" viewBox="0 0 1024 1024" width="48">
                            <path
                              d="M853.333333 320l-128 96v-85.333333a42.666667 42.666667 0 0 0-42.666666-42.666667H128a42.666667 42.666667 0 0 0-42.666667 42.666667v341.333333a42.666667 42.666667 0 0 0 42.666667 42.666667h554.666667a42.666667 42.666667 0 0 0 42.666666-42.666667v-85.333333l128 96a42.666667 42.666667 0 0 0 64-34.133334v-298.666666a42.666667 42.666667 0 0 0-64-34.133334z"
                              fill="#909399"
                            ></path>
                          </svg>
                        </div>
                      </div>
                      <div class="media-details">
                        <div class="info-content">
                          <div class="meta-item" style="display: flex; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
                            <span class="label">名称：</span>
                            <span class="value" :title="item.fileName || item.name || '-' ">{{ item.fileName || item.name || '-' }}</span>
                          </div>
                          <div class="meta-item">
                            <span class="label">时间：</span>
                            <span class="value">{{ item.createTime || item.time || '-' }}</span>
                          </div>
                        </div>
                        <div class="meta-actions">
                          <el-button
                            class="play-btn"
                            size="small"
                            type="primary"
                            @click="handleMediaAction(item)"
                            >{{ isMediaImage(item.fileUrl) ? '查看' : '播放' }}</el-button
                          >
                        </div>
                      </div>
                    </div>
                  </div>

                  <!-- 媒体区域分页 -->
                  <div class="media-pagination">
                    <el-pagination
                      v-model:current-page="mediaParams.current"
                      v-model:page-size="mediaParams.size"
                      layout="total, prev, pager, next"
                      small
                      :total="mediaTotal"
                      @current-change="getMediaList"
                    />
                  </div>
                </div>
              </div>
            </el-card>
          </div>
        </div>
      </el-col>
    </el-row>

    <!-- 轨迹时间段选择 -->
    <el-dialog
      v-model="trackDialogVisible"
      append-to-body
      title="轨迹回放配置"
      width="450px"
    >
      <el-form label-width="80px">
        <el-form-item label="编号">
          <span style="font-weight: 600; color: var(--text-primary)">{{ currentHat.hatNumber }}</span>
        </el-form-item>
        <el-form-item label="绑定人">
          <span style="font-weight: 600; color: var(--text-primary)">{{ currentHat.bindUserName }}</span>
        </el-form-item>
        <el-form-item label="快捷选择">
          <div class="quick-time-btns">
            <el-button size="small" @click="setQuickTime('1h')">最近1小时</el-button>
            <el-button size="small" @click="setQuickTime('today')">今天</el-button>
            <el-button size="small" @click="setQuickTime('yesterday')">昨天</el-button>
            <el-button size="small" @click="setQuickTime('week')">最近7天</el-button>
          </div>
        </el-form-item>
        <el-form-item label="时间段">
          <el-date-picker
            v-model="trackTimeRange"
            end-placeholder="结束时间"
            range-separator="至"
            start-placeholder="开始时间"
            style="width: 100%"
            type="datetimerange"
            value-format="YYYY-MM-DD HH:mm:ss"
          />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="trackDialogVisible = false">取消</el-button>
        <el-button type="primary" @click="confirmTrackPlayback"
          >开启回放</el-button
        >
      </template>
    </el-dialog>

    <!-- 媒体预览 -->
    <el-dialog
      v-model="previewVisible"
      append-to-body
      class="media-preview-dialog"
      :title="isVideoPreview ? '视频播放' : '图片查看'"
      width="60%"
      @close="closePreview"
    >
      <div v-if="previewUrl" class="preview-container" style="display: flex; justify-content: center; align-items: center; min-height: 300px;">
        <video
          v-if="isVideoPreview"
          ref="videoPlayer"
          autoplay
          controls
          :src="previewUrl"
          style="width: 100%; max-height: 60vh; outline: none; background-color: oklch(8% 0.005 250);"
        ></video>
        <el-image
          v-else
          fit="contain"
          :preview-src-list="[previewUrl]"
          :src="previewUrl"
          style="max-width: 100%; max-height: 60vh"
        ></el-image>
      </div>
    </el-dialog>
  </div>
</template>

<script setup name="Track">
import Pagination from '@/components/Pagination'
import TableSkeleton from '@/components/TableSkeleton'
import { hatSafetyInfoPage } from '@/api/helmet';
import { trackPlaybackQuery, getRelatedFiles } from '@/api/location';
import { useMap } from '@/hooks/useMap';
import 'ol/ol.css';

const { proxy } = getCurrentInstance();

const loading = ref(false);
const total = ref(0);
const hatList = ref([]);
const mediaList = ref([]);
const allMediaList = ref([]);
const mediaTotal = ref(0);
const trackDialogVisible = ref(false);
const trackTimeRange = ref([]);
const currentHat = ref({});
const isPlaying = ref(false);

const previewVisible = ref(false);
const previewUrl = ref('');
const isVideoPreview = ref(false);

function isMediaImage(url) {
  if (!url) return false;
  const lowerUrl = url.toLowerCase();
  return lowerUrl.endsWith('.jpg') || lowerUrl.endsWith('.jpeg') || lowerUrl.endsWith('.png') || lowerUrl.endsWith('.gif') || lowerUrl.endsWith('.bmp') || lowerUrl.endsWith('.webp');
}

function handleMediaAction(item) {
  if (!item.fileUrl) {
    proxy.$modal.msgWarning("文件地址为空");
    return;
  }
  previewUrl.value = item.fileUrl;
  isVideoPreview.value = !isMediaImage(item.fileUrl);
  previewVisible.value = true;
}

function closePreview() {
  previewUrl.value = '';
  previewVisible.value = false;
}

// 地图相关
const mapContainer = ref(null);
const trackData = ref([]);
// 保存地图实例和工具函数
let mapInstance = null;
let mapUtils = null;

const queryParams = reactive({
  current: 1,
  size: 12,
  hatIds: "",
});

const mediaParams = reactive({
  current: 1,
  size: 4,
});


/** 查询安全帽列表 */
function getList() {
  loading.value = true;
  hatSafetyInfoPage(queryParams).then((response) => {
    hatList.value = response.data.records;
    total.value = response.data.total;
    loading.value = false;
  }).catch(() => {
    loading.value = false;
  });
}

function handleQuery() {
  queryParams.current = 1;
  getList();
}

function handleTrackPlayback(row) {
  currentHat.value = row;
  trackTimeRange.value = [];
  trackDialogVisible.value = true;
}

/**
 * 设置快捷时间
 * @param {string} type - 快捷类型: '1h', 'today', 'yesterday', 'week'
 */
function setQuickTime(type) {
  const now = new Date();
  let startTime, endTime;

  const formatDate = (date) => {
    const y = date.getFullYear();
    const m = String(date.getMonth() + 1).padStart(2, '0');
    const d = String(date.getDate()).padStart(2, '0');
    const h = String(date.getHours()).padStart(2, '0');
    const min = String(date.getMinutes()).padStart(2, '0');
    const s = String(date.getSeconds()).padStart(2, '0');
    return `${y}-${m}-${d} ${h}:${min}:${s}`;
  };

  const startOfDay = (date) => {
    const d = new Date(date);
    d.setHours(0, 0, 0, 0);
    return d;
  };

  const endOfDay = (date) => {
    const d = new Date(date);
    d.setHours(23, 59, 59, 999);
    return d;
  };

  switch (type) {
    case '1h':
      startTime = new Date(now.getTime() - 60 * 60 * 1000);
      endTime = now;
      break;
    case 'today':
      startTime = startOfDay(now);
      endTime = endOfDay(now);
      break;
    case 'yesterday': {
      const yesterday = new Date(now.getTime() - 24 * 60 * 60 * 1000);
      startTime = startOfDay(yesterday);
      endTime = endOfDay(yesterday);
      break;
    }
    case 'week':
      startTime = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
      endTime = now;
      break;
    default:
      return;
  }

  trackTimeRange.value = [formatDate(startTime), formatDate(endTime)];
}

// 本地媒体分页
function getMediaList() {
  const start = (mediaParams.current - 1) * mediaParams.size;
  const end = start + mediaParams.size;
  mediaList.value = allMediaList.value.slice(start, end);
}

function confirmTrackPlayback() {
  if (!trackTimeRange.value || trackTimeRange.value.length !== 2) {
    proxy.$modal.msgWarning("请选择时间段");
    return;
  }

  const [startTime, endTime] = trackTimeRange.value;
  const data = {
    hatIds: [currentHat.value.bindUserId],
    startTime: startTime,
    endTime: endTime
  };

  const mediaData = {
    hatNumber: currentHat.value.hatNumber,
    startTime: startTime,
    endTime: endTime
  };

  const { playTrack, clearTrack } = mapUtils;

  Promise.all([
    trackPlaybackQuery(data),
    getRelatedFiles(mediaData)
  ]).then(([response, filesResponse]) => {
    trackDialogVisible.value = false;

    // 提取轨迹点数据
    let trackPoints = [];
    if (response.data && response.data.list && Array.isArray(response.data.list)) {
      trackPoints = response.data.list;
    } else if (response.data && Array.isArray(response.data)) {
      trackPoints = response.data;
    } else if (response.data && response.data.trackPoints) {
      trackPoints = response.data.trackPoints;
    } else if (response.data && response.data.rows) {
      trackPoints = response.data.rows;
    } else if (response.rows) {
      trackPoints = response.rows;
    }

    const normalizedTrackPoints = trackPoints
      .map((point) => {
        const lng = parseFloat(point.lng || point.longitude || point.lon || point.x);
        const lat = parseFloat(point.lat || point.latitude || point.y);
        return { coordinate: [lng, lat] };
      })
      .filter(({ coordinate }) => !isNaN(coordinate[0]) && !isNaN(coordinate[1]));

    const coordinates = normalizedTrackPoints.map((item) => item.coordinate);

    trackData.value = coordinates;

    // 检查是否有轨迹数据
    if (coordinates.length === 0) {
      proxy.$modal.msgWarning("该时间段内无轨迹数据");
      return;
    }

    // 开始回放
    isPlaying.value = true;
    mediaParams.current = 1;

    // 绘制轨迹
    const { playTrack, clearTrack } = mapUtils;
    if (coordinates.length > 0) {
      clearTrack();
      playTrack(coordinates);
    }

    // 从接口返回数据中获取媒体列表
    if (filesResponse.data && Array.isArray(filesResponse.data)) {
      allMediaList.value = filesResponse.data;
      mediaTotal.value = filesResponse.data.length;
    } else if (filesResponse.data && filesResponse.data.records) {
      allMediaList.value = filesResponse.data.records;
      mediaTotal.value = filesResponse.data.total || filesResponse.data.records.length;
    } else if (filesResponse.rows) {
      allMediaList.value = filesResponse.rows;
      mediaTotal.value = filesResponse.total || filesResponse.rows.length;
    } else if (filesResponse.data && filesResponse.data.mediaList) {
      allMediaList.value = filesResponse.data.mediaList;
      mediaTotal.value = filesResponse.data.mediaTotal || filesResponse.data.mediaList.length;
    } else {
      allMediaList.value = [];
      mediaTotal.value = 0;
    }

    getMediaList();
  }).catch((err) => {
    proxy.$modal.msgError("回放加载失败");
  });
}

function stopPlayback() {
  isPlaying.value = false;
  mediaList.value = [];
  allMediaList.value = [];
  // 清除轨迹
  if (mapUtils) {
    mapUtils.stopTrack(true);
    mapUtils.clearTrack();
  }
}

// 暂停轨迹回放
function handlePause() {
  if (mapUtils) {
    mapUtils.pauseTrack();
  }
}

// 继续/重新播放轨迹回放
function handlePlay() {
  if (!mapUtils) return;
  // 如果处于暂停状态，继续播放
  if (mapUtils.isPaused.value) {
    mapUtils.resumeTrack();
  } else if (trackData.value && trackData.value.length > 0) {
    // 动画已结束，重新播放
    const { clearTrack, playTrack } = mapUtils;
    clearTrack();
    playTrack(trackData.value);
  }
}

onMounted(() => {
  getList();
  // 初始化地图
  const utils = useMap();
  mapUtils = utils;
  mapInstance = utils.initMap(mapContainer.value);
});
</script>

<style scoped lang="scss">
.quick-time-btns {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;

  .el-button {
    font-size: 12px;
    padding: 6px 12px;
    background: transparent;
    border-color: var(--border-color);
    color: var(--text-secondary);

    &:hover,
    &:focus {
      background: var(--brand-primary);
      color: var(--color-primary-foreground);
      border-color: var(--color-primary);
    }

    &:active {
      background: var(--brand-primary);
      color: var(--color-primary-foreground);
      border-color: var(--color-primary);
    }
  }
}

.app-container {
  padding: 8px 24px 24px;
  height: calc(100vh - 60px);
  overflow: hidden;
  display: flex;
  flex-direction: column;
}

.sidebar-layout {
  flex: 1;
  min-height: 0;
}

.full-height {
  height: 100%;
}

.box-card {
  height: 100%;
  border-radius: var(--radius-lg);
  border: 1px solid var(--border-color);
  box-shadow: none;

  :deep(.el-card__body) {
    padding: 16px;
    height: 100%;
    display: flex;
    flex-direction: column;
  }
}

.list-card {
  :deep(.el-card__body) {
    padding: 16px;
    height: 100%;
    position: relative;
  }

  .search-box {
    margin-bottom: 12px;
  }
  .track-table {
    border-radius: var(--radius-lg);
    max-height: calc(100% - 120px);
    overflow: auto;
  }
  .pagination-wrapper {
    position: absolute;
    bottom: 16px;
    left: 16px;
    right: 16px;
    padding-top: 12px;
    border-top: 1px solid var(--border-color);
    display: flex;
    justify-content: flex-end;
    background: var(--bg-pure);
    z-index: 1;

    :deep(.pagination-container) {
      background: transparent;
      padding: 0;
      width: 100%;
    }

    :deep(.el-pagination) {
      justify-content: center;
      flex-wrap: wrap;
      row-gap: 8px;
      font-size: 13px;
      color: var(--text-secondary);
      font-weight: normal;

      .el-pagination__total {
        color: var(--text-secondary);
        font-size: 13px;
      }

      .el-pagination__sizes {
        .el-input {
          width: 80px;

          .el-input__wrapper {
            border-radius: var(--radius-lg);
            box-shadow: 0 0 0 1px var(--border-hover) inset;

            &:hover {
              box-shadow: 0 0 0 1px var(--border-focus) inset;
            }
          }
        }
      }

      .el-pagination__jump {
        color: var(--text-secondary);
        font-size: 13px;

        .el-input {
          width: 50px;
          margin: 0 8px;

          .el-input__wrapper {
            border-radius: var(--radius-lg);
            box-shadow: 0 0 0 1px var(--border-hover) inset;
          }
        }
      }

      .btn-prev,
      .btn-next {
        background: var(--bg-pure);
        border: 1px solid var(--border-color);
        border-radius: var(--radius-lg);
        min-width: 28px;
        height: 28px;
        color: var(--text-secondary);

        &:hover {
          color: var(--color-primary);
          border-color: var(--color-primary-light);
        }

        &:disabled {
          color: var(--text-muted);
          background: var(--bg-soft);
        }
      }

      .el-pager {
        li {
          background: var(--bg-pure);
          border: 1px solid var(--border-color);
          border-radius: var(--radius-lg);
          min-width: 28px;
          height: 28px;
          line-height: 26px;
          color: var(--text-secondary);
          margin: 0 4px;
          font-size: 13px;

          &:hover {
            color: var(--color-primary);
            border-color: var(--color-primary-light);
          }

          &.active {
            background: var(--color-primary);
            border-color: var(--color-primary);
            color: var(--color-primary-foreground);
          }
        }
      }
    }
  }
}

.right-content-area {
  height: 100%;
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.map-section {
  flex: 6;
  transition: flex 0.3s cubic-bezier(0.4, 0, 0.2, 1);
  min-height: 0;

  &.map-full {
    flex: 10;
  }
}

.media-section {
  flex: 4;
  min-height: 0;
  animation: slideUp 0.3s ease-out;
}

@keyframes slideUp {
  from {
    transform: translateY(20px);
    opacity: 0;
  }
  to {
    transform: translateY(0);
    opacity: 1;
  }
}

.map-card {
  position: relative;
  :deep(.el-card__body) {
    padding: 0;
  }
  .map-view {
    width: 100%;
    height: 100%;
    background: var(--bg-soft);
  }
  .track-controls {
    position: absolute;
    top: 16px;
    right: 16px;
    background: var(--bg-pure);
    padding: 6px 16px;
    border-radius: var(--radius-lg);
    display: flex;
    align-items: center;
    gap: 8px;
    box-shadow: var(--shadow-sm);
    z-index: 10;
    .track-info {
      font-size: 13px;
      font-weight: 500;
      display: flex;
      align-items: center;
      gap: 8px;
    }
    .status-indicator {
      width: 8px;
      height: 8px;
      background: var(--color-success);
      border-radius: 50%;
      animation: pulse 2s infinite;
    }
  }
}

@keyframes pulse {
  0% {
    transform: scale(0.95);
    box-shadow: 0 0 0 0 rgba(5, 150, 105, 0.7);
  }
  70% {
    transform: scale(1);
    box-shadow: 0 0 0 6px rgba(5, 150, 105, 0);
  }
  100% {
    transform: scale(0.95);
    box-shadow: 0 0 0 0 rgba(5, 150, 105, 0);
  }
}

.media-card {
  .section-header {
    margin-bottom: 15px;
    .title {
      font-size: 16px;
      font-weight: 700;
      color: var(--text-primary);
    }
  }
  .media-content {
    flex: 1;
    min-height: 0;

    .empty-state {
      height: 100%;
      display: flex;
      flex-direction: column;
      justify-content: center;
      align-items: center;
      color: var(--text-muted);
      gap: 8px;
      p {
        font-size: 14px;
      }
    }

    .media-grid-container {
      height: 100%;
      display: flex;
      flex-direction: column;

      .media-grid {
        //flex: 1;
        overflow: hidden;
        display: grid;
        grid-template-columns: repeat(4, 1fr);
        grid-template-rows: 1fr; /* 强制单行 */
        gap: 16px;
        padding-bottom: 10px;

        .media-card-item {
          background: var(--bg-pure);
          border: 1px solid var(--border-color);
          border-radius: 8px;
          overflow: hidden;
          transition: all 0.3s ease;
          display: flex;
          flex-direction: column;

          &:hover {
            transform: translateY(-4px);
            box-shadow: 0 12px 24px -8px rgba(0, 0, 0, 0.15);
            border-color: var(--color-primary);
          }

          .media-preview {
            height: 130px;
            background: var(--bg-muted);
            display: flex;
            justify-content: center;
            align-items: center;
            .video-placeholder {
              padding: 10px;
            }
          }

          .media-details {
            padding: 10px;
            display: flex;
            flex-direction: column;
            justify-content: space-between;
            flex: 1;

            .info-content {
              .meta-item {
                font-size: 14px;
                margin-bottom: 8px;
                display: flex;
                color: var(--text-secondary);
                &:last-child {
                  margin-bottom: 0;
                }
                .label {
                  white-space: nowrap;
                  flex-shrink: 0;
                }
                .value {
                  color: var(--text-primary);
                  text-overflow: ellipsis;
                  overflow: hidden;
                  white-space: nowrap;
                }
              }
            }

            .meta-actions {
              display: flex;
              justify-content: flex-end;
              margin-top: 10px;
              .play-btn {
                background: var(--color-primary);
                border: none;
                border-radius: var(--radius-lg);
                padding: 8px 18px;
                color: var(--color-primary-foreground);
                font-size: 13px;
              }
            }
          }
        }
      }

      .media-pagination {
        padding-top: 10px;
        display: flex;
        justify-content: flex-end;
      }
    }
  }
}

:deep(.el-table__header-wrapper th) {
  background-color: var(--bg-soft) !important;
  color: var(--text-secondary);
}

/* 全局禁用当前页面所有悬停动画效果 */
:deep(.el-card) {
  transition: none !important;

  &:hover {
    transform: none !important;
  }
}

:deep(.el-table) {
  transition: none !important;
}

/* 禁用表格行的悬停高亮效果 */
:deep(.el-table__body tr:hover > td.el-table__cell) {
  background-color: inherit !important;
}

/* 禁用按钮悬停位移效果 */
:deep(.el-button:hover) {
  transform: none !important;
}

/* 禁用标签悬停效果 */
:deep(.el-tag:hover) {
  transform: none !important;
}

/* 禁用输入框悬停效果 */
// :deep(.el-input__wrapper:hover) {
//   box-shadow: 0 0 0 1px var(--el-border-color) inset !important;
// }

/* 禁用分页按钮悬停效果 */
:deep(.el-pagination button:hover),
:deep(.el-pager li:hover) {
  transform: none !important;
}

/* 禁用链接按钮悬停效果 */
:deep(.el-button.is-link:hover) {
  transform: none !important;
}
</style>
