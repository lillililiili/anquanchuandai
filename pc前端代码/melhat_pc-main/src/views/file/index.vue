<template>
  <div class="app-container">
    <ModuleHeader module="file" />
    <!-- 头部搜索 -->
    <el-form
      v-show="showSearch"
      ref="queryRef"
      class="search-form"
      :inline="true"
      :model="queryParams"
    >
      <el-form-item label="人员姓名：" prop="userName">
        <el-input
          v-model="queryParams.userName"
          class="w-180"
          clearable
          placeholder="请输入姓名"
          @keyup.enter="handleQuery"
        />
      </el-form-item>
      <el-form-item label="文件类型：" prop="fileType">
        <el-select
          v-model="queryParams.fileType"
          class="w-180"
          clearable
          placeholder="全部"
        >
          <el-option label="全部" value="" />
          <el-option
            v-for="dict in file_type"
            :key="dict.value"
            :label="dict.label"
            :value="dict.value"
          />
        </el-select>
      </el-form-item>
      <el-form-item label="起止时间：" prop="dateRange">
        <el-date-picker
          v-model="dateRange"
          class="w-320"
          end-placeholder="结束时间"
          range-separator="至"
          start-placeholder="开始时间"
          type="datetimerange"
          value-format="YYYY-MM-DD HH:mm:ss"
        />
      </el-form-item>
      <el-form-item>
        <el-button class="search-btn" :disabled="searchLoading" icon="Search" :loading="searchLoading" type="primary" @click="handleQuery"
          >搜索</el-button
        >
        <el-button class="reset-btn" icon="Refresh" @click="resetQuery">清空</el-button>
      </el-form-item>
    </el-form>

    <!-- 文件卡片列表 -->
    <TableSkeleton v-if="loading && fileList.length === 0" :columns="4" :rows="4" />
    <div v-else v-loading="loading && fileList.length > 0" class="card-list-container">
      <el-row :gutter="20">
        <el-col v-for="item in fileList" :key="item.id" class="mb20" :lg="6" :md="8" :sm="12" :xs="24">
          <el-card class="file-card" :data-file-id="item.id">
            <div class="card-thumb-wrapper">
              <el-image 
                class="card-thumb" 
                :fetch-priority="getNormalizedFileType(item) === 'pic' ? 'high' : 'lazy'" 
                fit="cover"
                loading="lazy"
                :src="getCardThumbSrc(item)"
              >
                <template #error>
                  <div class="image-slot">
                    <el-icon v-if="getNormalizedFileType(item) === 'video'"><VideoPlay /></el-icon>
                    <el-icon v-else-if="getNormalizedFileType(item) === 'audio'"><Microphone /></el-icon>
                    <el-icon v-else><Picture /></el-icon>
                  </div>
                </template>
              </el-image>
              <div class="type-tag" :class="getNormalizedFileType(item)">
                <dict-tag plain :options="file_type" :value="item.fileType" />
              </div>
              <div class="card-actions">
                <el-button 
                  v-if="getFileTypeByUrl(item.fileUrl) !== 'pic'" 
                  circle 
                  :disabled="!item.fileUrl" 
                  icon="VideoPlay" 
                  :title="getFileTypeByUrl(item.fileUrl) === 'video' ? '播放视频' : '播放音频'"
                  type="primary"
                  @click="handlePlay(item)"
                />
                <el-button 
                  v-else 
                  circle 
                  :disabled="!item.fileUrl" 
                  icon="View" 
                  title="查看大图"
                  type="success"
                  @click="handleView(item)"
                />
              </div>
            </div>
            <div class="card-info">
              <div class="file-name" :title="item.fileName">{{ item.fileName }}</div>
              <div class="info-line">
                <span class="label">设备信息：</span>
                <span class="value">{{ item.deviceInfo || '-' }}</span>
              </div>
              <div class="info-line">
                <span class="label">采集时间：</span>
                <span class="value">{{ item.uploadTime }}</span>
              </div>
              <div class="info-line">
                <span class="label">文件大小：</span>
                <span class="value">{{ formatFileSize(item.fileSize) }}</span>
              </div>
            </div>
            <div class="card-footer-actions">
              <el-button 
                class="action-btn view-btn" 
                :disabled="!item.fileUrl"
                :icon="getFileTypeByUrl(item.fileUrl) === 'pic' ? 'View' : 'VideoPlay'"
                type="primary"
                @click="handleViewOrPlay(item)"
              >
                {{ getActionText(item.fileUrl) }}
              </el-button>
              <el-button 
                class="action-btn download-btn"
                :disabled="!item.fileUrl"
                icon="Download"
                @click="handleDownload(item)"
              >下载</el-button>
            </div>
          </el-card>
        </el-col>
      </el-row>

      <!-- 无数据 -->
      <BrandedEmpty v-if="fileList.length === 0" description="暂无文件数据" />
    </div>

    <!-- 分页 -->
    <el-row class="pg-container">
      <el-col :span="24">
        <pagination
          v-show="total > 0"
          v-model:limit="queryParams.size"
          v-model:page="queryParams.current"
          :total="total"
          @pagination="getList"
        />
      </el-col>
    </el-row>

    <!-- 视频播放弹窗 -->
    <el-dialog
      v-model="openPlay"
      append-to-body
      class="video-dialog"
      :title="currentFile.fileName"
      width="1000px"
      @close="handleMediaClose"
    >
      <div class="video-preview-box">
        <div class="video-mock-player">
          <video
            v-if="currentFile.fileType === 'video'"
            ref="videoRef"
            autoplay
            class="real-player"
            controls
            :src="currentFile.fileUrl"
          ></video>
          <audio
            v-else-if="currentFile.fileType === 'audio'"
            ref="audioRef"
            autoplay
            class="real-audio-player"
            controls
            :src="currentFile.fileUrl"
          ></audio>
        </div>
      </div>
    </el-dialog>

    <!-- 图片查看弹窗 -->
    <el-dialog
      v-model="openView"
      append-to-body
      class="image-dialog"
      :title="currentFile.fileName"
      width="1000px"
    >
      <div class="image-preview-box">
        <el-image class="preview-img" fit="contain" :src="currentFile.fileUrl">
          <template #error>
             <div class="image-slot">加载失败</div>
          </template>
        </el-image>
      </div>
    </el-dialog>
  </div>
</template>

<script setup name="File">
import { getFileRecordPage } from "@/api/file";
import { formatFileSize } from "@/utils/index";
import TableSkeleton from "@/components/TableSkeleton";
const { proxy } = getCurrentInstance();
const { file_type } = proxy.useDict("file_type");

const loading = ref(false);
const searchLoading = ref(false);
const showSearch = ref(true);
const total = ref(0);
const dateRange = ref([]);

const openPlay = ref(false);
const openView = ref(false);
const currentFile = ref({});
const videoCoverMap = ref({});
const videoRef = ref(null);
const audioRef = ref(null);

const queryParams = reactive({
  current: 1,
  size: 12,
  userName: '',
  fileType: '',
});

const fileList = ref([]);

// 缓存文件类型，避免模板中重复计算
const fileTypeCache = computed(() => {
  const cache = {};
  fileList.value.forEach(item => {
    cache[item.id] = {
      normalizedType: getNormalizedFileType(item),
      urlType: getFileTypeByUrl(item.fileUrl)
    };
  });
  return cache;
});

/** 生成缩略图URL - 假设后端支持 ?w=宽度 参数 */
function getThumbnailUrl(url, width = 400) {
  if (!url) return '';
  // 如果是完整URL，添加缩略图参数
  if (url.includes('?')) {
    return `${url}&w=${width}`;
  }
  return `${url}?w=${width}`;
}

/** 卡片缩略图，图片展示优化后的缩略图 */
function getCardThumbSrc(item) {
  const fileType = getNormalizedFileType(item);
  if (fileType === 'pic') {
    // 使用缩略图，最大宽度400px
    return getThumbnailUrl(item.fileUrl, 400) || '';
  }
  if (fileType === 'video') return videoCoverMap.value[item.fileUrl] || '';
  return '';
}

/** 搜索按钮操作 */
function handleQuery() {
  queryParams.current = 1;
  searchLoading.value = false;
  getList();
}

/** 重置按钮操作 */
function resetQuery() {
  dateRange.value = [];
  proxy.resetForm("queryRef");
  queryParams.current = 1;
  getList();
}

/** 根据扩展名判断文件类型 */
function getFileTypeByUrl(url) {
  if (!url) return 'unknown';
  const ext = url.split('.').pop().toLowerCase();
  const videoExts = ['mp4', 'm4v', 'mov', 'avi', 'wmv', 'flv', 'webm'];
  const audioExts = ['mp3', 'wav', 'm4a', 'aac', 'ogg', 'amr'];
  const picExts = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg'];
  
  if (videoExts.includes(ext)) return 'video';
  if (audioExts.includes(ext)) return 'audio';
  if (picExts.includes(ext)) return 'pic';
  return 'unknown';
}

/** 统一文件类型，保证样式和预览逻辑一致 */
function getNormalizedFileType(item) {
  if (!item) return 'unknown';
  if (item.fileType === 'image') return 'pic';
  if (item.fileType === 'picture') return 'pic';
  if (item.fileType === 'sound') return 'audio';
  if (item.fileType === 'voice') return 'audio';

  const fileType = item.fileType || getFileTypeByUrl(item.fileUrl);
  return fileType === 'unknown' ? getFileTypeByUrl(item.fileUrl) : fileType;
}

/** 为当前页视频异步生成首帧封面，使用IntersectionObserver延迟加载 */
let observer = null;

function loadVideoCovers(list) {
  // 如果已有observer，先断开
  if (observer) {
    observer.disconnect();
    observer = null;
  }
  
  const videoItems = (list || []).filter(item => {
    return getNormalizedFileType(item) === 'video' && item.fileUrl && !videoCoverMap.value[item.fileUrl];
  });

  if (!videoItems.length) return;

  // 使用IntersectionObserver延迟生成视频封面，只在可见时生成
  observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        const item = entry.target.__fileItem;
        if (item?.fileUrl && !videoCoverMap.value[item.fileUrl]) {
          captureVideoCover(item.fileUrl).then(cover => {
            if (cover) {
              videoCoverMap.value = {
                ...videoCoverMap.value,
                [item.fileUrl]: cover,
              };
            }
          });
          observer.unobserve(entry.target);
        }
      }
    });
  }, { rootMargin: '100px' });

  // 等待DOM更新后再观察
  setTimeout(() => {
    videoItems.forEach(item => {
      const card = document.querySelector(`[data-file-id="${item.id}"]`);
      if (card) {
        card.__fileItem = item;
        observer.observe(card);
      } else {
        // 如果没找到元素，直接生成封面（降级）
        captureVideoCover(item.fileUrl).then(cover => {
          if (cover) {
            videoCoverMap.value = { ...videoCoverMap.value, [item.fileUrl]: cover };
          }
        });
      }
    });
  }, 100);
}

/** 截取视频第一帧，失败时回退占位图 */
function captureVideoCover(url) {
  return new Promise((resolve) => {
    const video = document.createElement('video');
    let settled = false;

    const cleanup = () => {
      video.pause();
      video.removeAttribute('src');
      video.load();
      video.onloadeddata = null;
      video.onseeked = null;
      video.onerror = null;
    };

    const finish = (result = '') => {
      if (settled) return;
      settled = true;
      cleanup();
      resolve(result);
    };

    const drawFrame = () => {
      try {
        const canvas = document.createElement('canvas');
        canvas.width = video.videoWidth || 320;
        canvas.height = video.videoHeight || 180;
        const context = canvas.getContext('2d');
        if (!context) {
          finish('');
          return;
        }
        context.drawImage(video, 0, 0, canvas.width, canvas.height);
        finish(canvas.toDataURL('image/jpeg', 0.85));
      } catch {
        finish('');
      }
    };

    const seekToFirstFrame = () => {
      if (video.readyState < 2) return;
      try {
        video.currentTime = Math.min(0.1, Math.max(video.duration || 0, 0));
      } catch {
        drawFrame();
      }
    };

    const timeoutId = window.setTimeout(() => finish(''), 8000);
    const complete = (result = '') => {
      window.clearTimeout(timeoutId);
      finish(result);
    };

    video.preload = 'metadata';
    video.muted = true;
    video.playsInline = true;
    video.crossOrigin = 'anonymous';
    video.onloadeddata = seekToFirstFrame;
    video.onseeked = () => {
      try {
        const canvas = document.createElement('canvas');
        canvas.width = video.videoWidth || 320;
        canvas.height = video.videoHeight || 180;
        const context = canvas.getContext('2d');
        if (!context) {
          complete('');
          return;
        }
        context.drawImage(video, 0, 0, canvas.width, canvas.height);
        complete(canvas.toDataURL('image/jpeg', 0.85));
      } catch {
        complete('');
      }
    };
    video.onerror = () => complete('');
    video.src = url;
  });
}

/** 获取按钮文字 */
function getActionText(url) {
  if (!url) return '无地址';
  const type = getFileTypeByUrl(url);
  if (type === 'video') return '播放';
  if (type === 'audio') return '收听';
  if (type === 'pic') return '查看';
  return '处理';
}

/** 统一查看/播放操作 */
function handleViewOrPlay(item) {
  const type = getFileTypeByUrl(item.fileUrl);
  if (type === 'video' || type === 'audio') {
    handlePlay(item);
  } else if (type === 'pic') {
    handleView(item);
  } else {
    proxy.$modal.msgWarning("不支持预览该类型文件，请直接下载");
  }
}

/** 播放视频/音频 */
function handlePlay(row) {
  currentFile.value = {
    ...row,
    fileType: getFileTypeByUrl(row.fileUrl) // 确保弹窗里的类型也是基于扩展名
  };
  openPlay.value = true;
}

/** 查看图片 */
function handleView(row) {
  currentFile.value = row;
  openView.value = true;
}

/** 弹窗关闭时停止媒体播放 */
function handleMediaClose() {
  if (videoRef.value) {
    videoRef.value.pause();
    videoRef.value.currentTime = 0;
  }
  if (audioRef.value) {
    audioRef.value.pause();
    audioRef.value.currentTime = 0;
  }
}

/** 下载文件 */
function handleDownload(row) {
  if (row.fileUrl) {
    window.open(row.fileUrl, '_blank');
  } else {
    proxy.$modal.msgError("文件地址不存在");
  }
}

/** 获取文件列表 */
function getList() {
  const query = {
    ...queryParams,
  };
  // 处理时间范围参数
  if (dateRange.value && dateRange.value.length === 2) {
    query.startTime = dateRange.value[0];
    query.endTime = dateRange.value[1];
  }
  loading.value = true;
  getFileRecordPage(query).then(res => {
    loading.value = false;
    if (res.code === 200) {
      fileList.value = res.data?.records || [];
      total.value = res.data?.total || 0;
      // 为当前页视频生成封面
      loadVideoCovers(fileList.value);
    }
  }).catch(() => {
    loading.value = false;
  });
}

getList();

onBeforeUnmount(() => {
  if (observer) {
    observer.disconnect();
    observer = null;
  }
});
</script>

<style scoped lang="scss">
.app-container {
  padding: 8px var(--section-padding) var(--section-padding);
}

.search-form {
  margin-bottom: var(--space-5);
  padding: var(--space-4) var(--section-padding);
  background: var(--bg-pure);
  border-radius: 12px;
  box-shadow: var(--shadow-sm);

  :deep(.el-form-item) {
    margin-right: var(--section-padding);
    margin-bottom: 0;
    label { font-weight: var(--font-medium); color: var(--text-secondary); }
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

.reset-btn {
  color: var(--text-secondary);
  border-color: var(--border-hover);
}

.card-list-container {
  min-height: 400px;
}

.file-card {
  border-radius: 12px;
  overflow: hidden;
  border: 1px solid var(--border-color);
  box-shadow: var(--shadow-sm);
  text-align: left;

  :deep(.el-card__body) {
    padding: 0 !important;
  }

  &:hover {
    transform: none !important;
    box-shadow: var(--shadow-sm) !important;
  }
}

.card-thumb-wrapper {
  width:100%;
  height: 180px;
  aspect-ratio: 16 / 9;
  overflow: hidden;
  position: relative;
  background: var(--bg-soft);

  .card-thumb {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  .image-slot {
    display: flex;
    justify-content: center;
    align-items: center;
    height: 100%;
    font-size: var(--text-2xl);
    color: var(--text-muted);
  }

  .type-tag {
    position: absolute;
    top: var(--space-3);
    left: var(--space-3);
    padding: var(--space-1) var(--space-3);
    border-radius: var(--radius);
    font-size: var(--text-xs);
    font-weight: var(--font-semibold);
    color: var(--color-primary);
    background: var(--bg-selected);
    border: 1px solid #c9dcf7;
    z-index: 1;

    &.video { color: var(--color-primary); background: #eaf2ff; border-color: #c9dcf7; }
    &.pic { color: #15845c; background: #edf7f2; border-color: #cce7da; }
    &.audio { color: #148b98; background: #eaf6f7; border-color: #c4e3e6; }
  }
}

.card-info {
  padding: var(--space-5) var(--space-5) 0;
  border-bottom: 1px solid var(--border-color);

  .file-name {
    font-size: var(--text-lg);
    font-weight: var(--font-bold);
    color: var(--text-primary);
    margin-bottom: var(--space-4);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    text-align: left;
  }

  .info-line {
    font-size: var(--text-sm);
    margin-bottom: var(--space-2);
    display: flex;
    justify-content: flex-start;

    .label { color: var(--text-muted); width: 75px; flex-shrink: 0; }
    .value { color: var(--text-secondary); font-weight: var(--font-medium); }

    &:last-child { margin-bottom: 0; }
  }
}

.card-footer-actions {
  padding: var(--space-4) var(--space-5);
  display: flex;
  gap: var(--space-4);

  .action-btn {
    flex: 1;
    height: 40px;
    border-radius: 8px;
    font-weight: var(--font-semibold);
    font-size: var(--text-sm);
    margin: 0;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .play-btn, .view-btn {
    background-color: var(--color-primary);
    border-color: var(--color-primary);
    color: #fff;
    &:hover:not(.is-disabled) { background-color: var(--color-primary-hover); border-color: var(--color-primary-hover); }
    &.is-disabled {
      background-color: var(--bg-soft) !important;
      border-color: var(--border-color) !important;
      color: var(--text-muted) !important;
    }
  }

  .download-btn {
    background-color: var(--bg-pure);
    border: 1px solid var(--border-color);
    color: var(--text-secondary);
    &:hover:not(.is-disabled) { background-color: var(--bg-soft); border-color: var(--border-hover); }
    &.is-disabled {
      background-color: var(--bg-soft) !important;
      color: var(--border-color) !important;
      border-color: var(--bg-muted) !important;
    }
  }
}

.pg-container {
  margin-top: var(--section-padding);
  display: flex;
  justify-content: flex-end;
}

// 弹窗样式
.video-dialog, .image-dialog {
  :deep(.el-dialog) {
    border-radius: 12px;
    overflow: hidden;
  }
  :deep(.el-dialog__header) {
    padding: var(--space-5) var(--section-padding);
    margin: 0;
    border-bottom: 1px solid var(--border-color);
  }
  :deep(.el-dialog__body) {
    padding: 0;
  }
}

.video-preview-box {
  .real-player {
    width: 100%;
    height: 560px;
    background: oklch(8% 0.005 250);
    display: block;
  }
  .real-audio-player {
    width: 80%;
    margin: var(--space-10) auto;
    display: block;
  }
}

.image-preview-box {
  background: var(--bg-soft);
  .preview-img {
    width: 100%;
    max-height: 600px;
    display: block;
  }
  .image-slot {
    display: flex;
    justify-content: center;
    align-items: center;
    height: 100%;
    color: var(--text-muted);
  }
}

.mb20 { margin-bottom: var(--space-5); }
</style>
