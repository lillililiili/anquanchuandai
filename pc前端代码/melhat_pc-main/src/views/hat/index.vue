<template>
  <div class="app-container">
    <ModuleHeader module="hat" />
    <!-- 统计卡片 -->
    <el-row class="mb2" :gutter="20">
      <el-col :md="8" :sm="8" :xs="24">
        <div class="stat-card">
          <img class="stat-art" alt="" aria-hidden="true" src="/visuals/hat.webp" />
          <div class="stat-icon-wrapper blue">
            <el-icon><Monitor /></el-icon>
          </div>
          <div class="stat-content">
            <div class="stat-value">{{ statData.total }}</div>
            <div class="stat-label">安全帽总数</div>
          </div>
        </div>
      </el-col>
      <el-col :md="8" :sm="8" :xs="24">
        <div class="stat-card">
          <img class="stat-art" alt="" aria-hidden="true" src="/visuals/hat.webp" />
          <div class="stat-icon-wrapper green">
            <el-icon><CircleCheck /></el-icon>
          </div>
          <div class="stat-content">
            <div class="stat-value">{{ statData.online }}</div>
            <div class="stat-label">正常使用</div>
          </div>
        </div>
      </el-col>
      <el-col :md="8" :sm="8" :xs="24">
        <div class="stat-card">
          <img class="stat-art" alt="" aria-hidden="true" src="/visuals/hat.webp" />
          <div class="stat-icon-wrapper red">
            <el-icon><CircleClose /></el-icon>
          </div>
          <div class="stat-content">
            <div class="stat-value">{{ statData.offline }}</div>
            <div class="stat-label">已离线</div>
          </div>
        </div>
      </el-col>
    </el-row>

    <el-form
      v-show="showSearch"
      ref="queryRef"
      class="search-form"
      :inline="true"
      :model="queryParams"
    >
      <el-form-item label="安全帽编号：" prop="hatNumber">
        <el-input
          v-model="queryParams.hatNumber"
          class="w-180"
          clearable
          placeholder="请输入安全帽编号"
          @keyup.enter="handleQuery"
        />
      </el-form-item>
      <el-form-item label="人员姓名：" prop="bindUserName">
        <el-input
          v-model="queryParams.bindUserName"
          class="w-180"
          clearable
          placeholder="请输入人员姓名"
          @keyup.enter="handleQuery"
        />
      </el-form-item>
      <el-form-item label="所属群组：" prop="bindGroup">
        <el-select
          v-model="queryParams.bindGroup"
          class="w-180"
          clearable
          placeholder="全部"
        >
          <el-option
            v-for="item in groupOptions"
            :key="item.id"
            :label="item.groupName"
            :value="item.groupName"
          />
        </el-select>
      </el-form-item>
      <el-form-item label="状态：" prop="status">
        <el-select
          v-model="queryParams.status"
          class="w-180"
          clearable
          placeholder="全部"
        >
          <el-option label="正常使用" :value="1" />
          <el-option label="已离线" :value="0" />
        </el-select>
      </el-form-item>
      <el-form-item label="绑定时间：" prop="dateRange">
        <el-date-picker
          v-model="dateRange"
          class="w-240"
          end-placeholder="结束时间"
          range-separator="至"
          start-placeholder="开始时间"
          type="daterange"
          value-format="YYYY-MM-DD"
        />
      </el-form-item>
      <el-form-item>
        <el-button
          class="search-btn"
          :disabled="searchLoading"
          icon="Search"
          :loading="searchLoading"
          type="primary"
          @click="handleQuery"
          >搜索</el-button
        >
        <el-button class="reset-btn" icon="Refresh" @click="resetQuery"
          >清空</el-button
        >
      </el-form-item>
    </el-form>

    <el-row class="mb16 action-bar" :gutter="10">
      <el-col :span="1.5">
        <el-button class="add-btn" icon="Plus" type="primary" @click="handleAdd"
          >新增安全帽</el-button
        >
      </el-col>
    </el-row>

    <TableSkeleton v-if="loading && helmetList.length === 0" :columns="10" :rows="5" />
    <el-table
      v-else
      v-loading="loading && helmetList.length > 0"
      class="custom-table"
      :data="helmetList"
      style="width: 100%"
    >
      <template #empty><BrandedEmpty compact description="暂无记录" /></template>
      <el-table-column align="center" label="序号" type="index" width="65" />
      <el-table-column
        align="center"
        label="安全帽编号"
        min-width="120"
        prop="hatNumber"
      />
      <el-table-column
        align="center"
        label="所属群组"
        prop="bindGroup"
        width="100"
      />
      <el-table-column
        align="center"
        label="绑定人员姓名"
        prop="bindUserName"
        width="120"
      />
      <el-table-column
        align="center"
        label="绑定时间"
        min-width="170"
        prop="bindTime"
      />
      <el-table-column align="center" label="电量" width="180">
        <template #default="scope">
          <div class="progress-wrapper">
            <el-progress
              :color="getProgressColor(scope.row.electricityUsage)"
              :percentage="scope.row.electricityUsage || 0"
              :stroke-width="8"
            />
          </div>
        </template>
      </el-table-column>
      <el-table-column align="center" label="存储空间" width="180">
        <template #default="scope">
          <div class="progress-wrapper">
            <el-progress
              :color="getProgressColor(scope.row.storageUsage)"
              :percentage="scope.row.storageUsage || 0"
              :stroke-width="8"
            />
          </div>
        </template>
      </el-table-column>
      <el-table-column
        align="center"
        label="录音"
        prop="recordCount"
        width="80"
      >
        <template #default="scope">
          <div v-if="scope.row.recordCount > 0" class="media-cell">
            <el-tooltip content="点击播放录音" placement="top">
              <el-button aria-label="点击播放录音"
                icon="Microphone"
                link
                type="primary"
                @click="handlePlayAudio(scope.row)"
              >
                <span class="count-text ml4">{{ scope.row.recordCount }}</span>
              </el-button>
            </el-tooltip>
          </div>
          <span v-else class="count-text gray">-</span>
        </template>
      </el-table-column>
      <el-table-column
        align="center"
        label="图片"
        prop="photoCount"
        width="100"
      >
        <template #default="scope">
          <div v-if="scope.row.photoCount > 0" class="media-cell">
            <image-preview
              v-if="scope.row.photoUrl"
              height="40px"
              :src="scope.row.photoUrl"
              width="40px"
            />
            <el-button
              v-else
              icon="Picture"
              link
              type="primary"
              @click="handlePreviewImage(scope.row)"
            >
              <span class="count-text ml4">{{ scope.row.photoCount }}</span>
            </el-button>
          </div>
          <span v-else class="count-text gray">-</span>
        </template>
      </el-table-column>
      <el-table-column
        align="center"
        label="视频"
        prop="videoCount"
        width="100"
      >
        <template #default="scope">
          <div v-if="scope.row.videoCount > 0" class="media-cell">
            <el-tooltip content="点击播放视频" placement="top">
              <el-button aria-label="点击播放视频"
                icon="VideoPlay"
                link
                type="primary"
                @click="handlePlayVideo(scope.row)"
              >
                <span class="count-text ml4">{{ scope.row.videoCount }}</span>
              </el-button>
            </el-tooltip>
          </div>
          <span v-else class="count-text gray">-</span>
        </template>
      </el-table-column>
      <el-table-column align="center" label="状态" prop="statusText" width="100">
        <template #default="scope">
          <el-tag
            :class="scope.row.status === 0 ? 'gray-tag' : ''"
            effect="light"
            :type="scope.row.status === 1 ? 'success' : 'info'"
          >
            {{ scope.row.statusText || (scope.row.status === 1 ? '正常使用' : '已离线') }}
          </el-tag>
        </template>
      </el-table-column>
      <el-table-column align="center" label="操作" width="180">
        <template #default="scope">
          <div class="operation-buttons">
            <el-tooltip content="详情" placement="top">
              <el-button aria-label="详情"
                icon="View"
                link
                type="primary"
                @click="handleDetail(scope.row)"
              ></el-button>
            </el-tooltip>
            <el-tooltip content="修改" placement="top">
              <el-button aria-label="修改"
                icon="Edit"
                link
                type="primary"
                @click="handleUpdate(scope.row)"
              ></el-button>
            </el-tooltip>
            <el-tooltip content="删除" placement="top">
              <el-button aria-label="删除"
                icon="Delete"
                link
                type="danger"
                @click="handleDelete(scope.row)"
              ></el-button>
            </el-tooltip>
          </div>
        </template>
      </el-table-column>
    </el-table>

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

    <!-- 添加或修改安全帽对话框 -->
    <el-dialog
      v-model="open"
      append-to-body
      class="custom-dialog"
      :title="title"
      width="600px"
    >
      <el-form ref="helmetRef" label-width="120px" :model="form" :rules="rules">
        <el-form-item label="安全帽编号：" prop="hatNumber">
          <el-input
            v-model="form.hatNumber"
            maxlength="30"
            placeholder="限制30个字以内"
          />
        </el-form-item>
        <el-form-item label="所属群组：" prop="bindGroup">
          <el-select
            v-model="form.bindGroup"
            placeholder="请选择"
            style="width: 100%"
            @change="handleGroupChange"
          >
            <el-option
              v-for="item in groupOptions"
              :key="item.id"
              :label="item.groupName"
              :value="item.groupName"
            />
          </el-select>
        </el-form-item>
        <el-form-item label="绑定人员姓名：" prop="bindUserId">
          <el-select
            v-model="form.bindUserId"
            clearable
            filterable
            placeholder="请选择人员"
            style="width: 100%"
            @change="handleUserChange"
          >
            <el-option
              v-for="item in userOptions"
              :key="item.userId"
              :label="item.nickName"
              :value="item.userId"
            />
          </el-select>
        </el-form-item>
      </el-form>
      <template #footer>
        <div class="dialog-footer">
          <el-button class="dialog-cancel-btn" @click="cancel">取 消</el-button>
          <el-button class="dialog-save-btn" type="primary" @click="submitForm"
            >保 存</el-button
          >
        </div>
      </template>
    </el-dialog>

    <!-- 详情对话框 -->
    <el-dialog
      v-model="openDetail"
      append-to-body
      class="custom-dialog"
      title="详情"
      width="600px"
    >
      <el-form disabled label-width="120px" :model="form">
        <el-form-item label="安全帽编号：">
          <el-input v-model="form.hatNumber" />
        </el-form-item>
        <el-form-item label="所属群组：">
          <el-input v-model="form.bindGroup" />
        </el-form-item>
        <el-form-item label="绑定人员姓名：">
          <el-input v-model="form.bindUserName" />
        </el-form-item>
        <el-form-item label="绑定时间：">
          <el-input v-model="form.bindTime" />
        </el-form-item>
      </el-form>
      <template #footer>
        <div class="dialog-footer">
          <el-button
            class="dialog-save-btn"
            type="primary"
            @click="openDetail = false"
            >关 闭</el-button
          >
        </div>
      </template>
    </el-dialog>

    <!-- 视频播放对话框 -->
    <el-dialog
      v-model="videoOpen"
      append-to-body
      class="custom-dialog"
      destroy-on-close
      title="视频预览"
      width="800px"
    >
      <div class="media-player-container">
        <video
          v-if="videoUrl"
          autoplay
          class="media-video"
          controls
          :src="videoUrl"
        ></video>
        <BrandedEmpty v-else description="暂无视频地址" />
      </div>
    </el-dialog>

    <!-- 录音播放对话框 -->
    <el-dialog
      v-model="audioOpen"
      append-to-body
      class="custom-dialog"
      destroy-on-close
      title="录音播放"
      width="500px"
    >
      <div class="media-player-container audio-container">
        <div class="audio-info mb20">
          <el-icon class="audio-icon"><Microphone /></el-icon>
          <div class="audio-title">正在播放录音</div>
        </div>
        <audio
          v-if="audioUrl"
          autoplay
          class="media-audio"
          controls
          :src="audioUrl"
        ></audio>
        <BrandedEmpty v-else description="暂无录音地址" />
      </div>
    </el-dialog>
</div>
</template>

<script setup name="Hat">
import { hatSafetyInfoPage, hatSafetyInfoList, hatSafetyInfoUpdate, hatSafetyInfoSave, hatSafetyInfoDelete } from "@/api/helmet";
import { groupList as getGroupList } from "@/api/group";
import { listUser } from "@/api/system/user";
import TableSkeleton from "@/components/TableSkeleton";

const { proxy } = getCurrentInstance();

const helmetList = ref([]);

const open = ref(false);
// 详情对话框
const openDetail = ref(false);
const videoOpen = ref(false);
const audioOpen = ref(false);
const videoUrl = ref("");
const audioUrl = ref("");
const baseUrl = import.meta.env.VITE_APP_BASE_API;

const loading = ref(false);
const searchLoading = ref(false);
const showSearch = ref(true);
const groupOptions = ref([]);
const userOptions = ref([]);
const total = ref(0);
const title = ref("");

// 统计数据
const statData = ref({
  total: 0,
  online: 0,
  offline: 0,
});

const data = reactive({
  form: {},
  queryParams: {
    current: 1,
    size: 10,
    hatNumber: undefined,
    bindUserName: undefined,
    bindGroup: undefined,
    status: undefined,
    startTime: undefined,
    endTime: undefined,
  },
  rules: {
    hatNumber: [
      { required: true, message: "安全帽编号不能为空", trigger: "blur" },
    ],
    bindGroup: [{ required: true, message: "所属群组不能为空", trigger: "change" }],
  },
});

const { queryParams, form, rules } = toRefs(data);

// 日期范围
const dateRange = ref([]);

/** 查询安全帽列表 */
function getList() {
  loading.value = true;
  searchLoading.value = true;
  // 设置日期参数
  if (dateRange.value && dateRange.value.length === 2) {
    queryParams.value.startTime = dateRange.value[0] + ' 00:00:00';
    queryParams.value.endTime = dateRange.value[1] + ' 23:59:59';
  } else {
    queryParams.value.startTime = undefined;
    queryParams.value.endTime = undefined;
  }

  hatSafetyInfoPage(queryParams.value).then(response => {
    const resData = response.data;
    helmetList.value = resData.records || [];
    total.value = resData.total || 0;
  }).catch(() => {
  }).finally(() => {
    loading.value = false;
    searchLoading.value = false;
  });
}

/** 获取统计数据（基于全量列表） */
function getStatData() {
  hatSafetyInfoList().then(response => {
    const list = response.data || [];
    const online = list.filter(item => item.status == 1).length;
    const offline = list.filter(item => item.status == 0).length;
    statData.value = {
      total: list.length,
      online,
      offline,
    };
  }).catch(() => {});
}

// 取消按钮
function cancel() {
  open.value = false;
  reset();
}

// 表单重置
function reset() {
  form.value = {
    id: undefined,
    hatNumber: undefined,
    bindGroup: undefined,
    bindGroupId: undefined,
    bindUserId: undefined,
    bindUserName: undefined,
    status: "0",
  };
  proxy.resetForm("helmetRef");
}

/** 获取分组列表 */
function getGroupOptions() {
  getGroupList({ pageNo: 1, pageSize: 999 }).then(response => {
    groupOptions.value = response.data?.records || [];
  }).catch(() => {});
}

/** 获取用户列表 */
function getUserOptions() {
  listUser({ pageNum: 1, pageSize: 999 }).then(response => {
    userOptions.value = response.rows || [];
  }).catch(() => {});
}

/** 搜索按钮操作 */
function handleQuery() {
  queryParams.value.current = 1;
  getList();
}

/** 重置按钮操作 */
function resetQuery() {
  dateRange.value = [];
  proxy.resetForm("queryRef");
  handleQuery();
}

/** 新增按钮操作 */
function handleAdd() {
  reset();
  open.value = true;
  title.value = "新增安全帽";
}

/** 修改按钮操作 */
function handleUpdate(row) {
  reset();
  form.value = { ...row };
  open.value = true;
  title.value = "修改";
}

/** 提交按钮 */
function submitForm() {
  proxy.$refs["helmetRef"].validate((valid) => {
    if (valid) {
      if (form.value.hatId) {
        // 修改
        hatSafetyInfoUpdate(form.value).then(() => {
          proxy.$modal.msgSuccess("修改成功");
          open.value = false;
          getList();
          getStatData();
        });
      } else {
        // 新增
        hatSafetyInfoSave(form.value).then(() => {
          proxy.$modal.msgSuccess("新增成功");
          open.value = false;
          getList();
          getStatData();
        });
      }
    }
  });
}

/** 删除按钮操作 */
function handleDelete(row) {
  const hatNumber = row.hatNumber || "选中项";

  proxy.$modal
    .confirm('是否确认删除安全帽编号为"' + hatNumber + '"的数据项？')
    .then(() => {
      return hatSafetyInfoDelete(row.id);
    })
    .then(() => {
      proxy.$modal.msgSuccess("删除成功");
      getList();
    })
    .catch(() => {});
}

/** 详情按钮操作 */
function handleDetail(row) {
  form.value = { ...row };
  openDetail.value = true;
}

/** 播放视频 */
function handlePlayVideo(row) {
  if (row.videoUrl) {
    videoUrl.value = row.videoUrl.startsWith('http') ? row.videoUrl : baseUrl + row.videoUrl;
    videoOpen.value = true;
  } else {
    proxy.$modal.msgWarning("该记录暂无视频地址");
  }
}

/** 播放录音 */
function handlePlayAudio(row) {
  if (row.recordUrl) {
    audioUrl.value = row.recordUrl.startsWith('http') ? row.recordUrl : baseUrl + row.recordUrl;
    audioOpen.value = true;
  } else {
    proxy.$modal.msgWarning("该记录暂无录音地址");
  }
}

/** 预览图片 */
function handlePreviewImage(row) {
  if (row.photoUrl) {
    // 如果没有使用 image-preview 组件直接点击的情况
    const url = row.photoUrl.startsWith('http') ? row.photoUrl : baseUrl + row.photoUrl;
    // 这里可以触发一个图片查看逻辑，或者简单提示
    proxy.$modal.msgInfo("请点击图片进行预览");
  } else {
    proxy.$modal.msgWarning("该记录暂无图片地址");
  }
}

/** 用户选择变化 */
function handleUserChange(val) {
  const user = userOptions.value.find(item => item.userId === val);
  if (user) {
    form.value.bindUserName = user.nickName;
  } else {
    form.value.bindUserName = undefined;
  }
}

/** 群组选择变化 */
function handleGroupChange(val) {
  const group = groupOptions.value.find(item => item.groupName === val);
  if (group) {
    form.value.bindGroupId = group.id;
  } else {
    form.value.bindGroupId = undefined;
  }
}

// 缓存CSS变量颜色，避免每次计算时都读取DOM
const progressColors = ref({
  danger: '#dc2626',
  warning: '#f59e0b',
  success: '#059669'
});

// 组件挂载时一次性读取CSS变量
onMounted(() => {
  const rootStyle = getComputedStyle(document.documentElement);
  progressColors.value = {
    danger: rootStyle.getPropertyValue('--color-danger').trim() || '#dc2626',
    warning: rootStyle.getPropertyValue('--color-warning').trim() || '#f59e0b',
    success: rootStyle.getPropertyValue('--color-success').trim() || '#059669'
  };
});

/** 获取进度条颜色 - 使用缓存值 */
function getProgressColor(percentage) {
  if (percentage < 30) return progressColors.value.danger;
  if (percentage < 60) return progressColors.value.warning;
  return progressColors.value.success;
}

getList();
getStatData();
getGroupOptions();
getUserOptions();
</script>

<style scoped lang="scss">
@import "@/assets/styles/variables.module.scss";

.app-container {
  padding: 8px var(--section-padding) var(--section-padding);
  min-height: 100%;
}

// 统计卡片样式
.stat-card {
  display: flex;
  align-items: center;
  padding: var(--section-padding);
  background: var(--bg-pure);
  border-radius: 12px;
  box-shadow: var(--shadow-sm);
  transition: all 0.3s ease;

  &:hover {
    box-shadow: var(--shadow-md);
    transform: translateY(-2px);
  }

  .stat-icon-wrapper {
    width: 56px;
    height: 56px;
    border-radius: 12px;
    display: flex;
    align-items: center;
    justify-content: center;
    margin-right: var(--space-4);
    font-size: var(--text-xl);

    &.blue {
      background-color: var(--color-info-bg);
      color: var(--color-info);
    }
    &.green {
      background-color: var(--color-success-bg);
      color: var(--color-success);
    }
    &.red {
      background-color: var(--color-danger-bg);
      color: var(--color-danger);
    }
  }

  .stat-value {
    font-size: var(--text-2xl);
    font-weight: var(--font-bold);
    color: var(--text-primary);
    line-height: var(--leading-tight);
  }

  .stat-label {
    font-size: var(--text-sm);
    color: var(--text-secondary);
    margin-top: var(--space-1);
  }
}

.search-form {
  margin-top: var(--space-3);
  margin-bottom: var(--space-3);
  padding: var(--space-4) var(--section-padding);
  background: var(--bg-pure);
  border-radius: 12px;
  box-shadow: var(--shadow-sm);

  :deep(.el-form-item) {
    margin-right: var(--section-padding);
    margin-bottom: var(--space-3);

    .el-form-item__label {
      font-weight: var(--font-medium);
      color: var(--text-secondary) !important;
    }
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

.action-bar {
  margin-bottom: var(--space-4);
}

.add-btn {
  background-color: var(--color-dark-action);
  border-color: var(--color-dark-action);
  padding: var(--space-3) var(--space-5);
  &:hover {
    background-color: var(--color-dark-action-hover);
    border-color: var(--color-dark-action-hover);
  }
}

.custom-table {
  border-radius: 12px;
  overflow: hidden;
  box-shadow: var(--shadow-sm);

  :deep(.el-table__header-wrapper) {
    th {
      background-color: var(--bg-table-header);
      color: var(--text-primary);
      font-weight: var(--font-semibold);
      height: 56px;
    }
  }

  :deep(.el-table__row) {
    height: 72px;
    td {
      border-bottom: 1px solid var(--border-color);
    }
  }
}

.progress-wrapper {
  padding: 0 var(--space-3);
  :deep(.el-progress-bar__inner) {
    background-image: none;
  }
}

.count-text {
  color: var(--color-danger);
  font-weight: var(--font-medium);
  &.gray {
    color: var(--text-muted);
  }
}

.media-cell {
  display: flex;
  justify-content: center;
  align-items: center;
  .ml4 {
    margin-left: var(--space-1);
  }
}

.media-player-container {
  padding: var(--space-5);
  display: flex;
  flex-direction: column;
  align-items: center;
  background: var(--bg-soft);
  border-radius: 8px;

  &.audio-container {
    padding: var(--space-10) var(--space-5);
  }

  .media-video {
    width: 100%;
    max-height: 500px;
    border-radius: 8px;
    box-shadow: 0 4px 12px rgba(0,0,0,0.1);
  }

  .media-audio {
    width: 100%;
  }

  .audio-info {
    display: flex;
    flex-direction: column;
    align-items: center;
    margin-bottom: var(--section-padding);
    .audio-icon {
      font-size: var(--text-3xl);
      color: var(--color-action);
      margin-bottom: var(--space-3);
    }
    .audio-title {
      font-size: var(--text-lg);
      font-weight: var(--font-semibold);
      color: var(--text-primary);
    }
  }
}

.status-text {
  font-weight: var(--font-medium);
  &.text-primary {
    color: var(--color-info);
  }
  &.text-danger {
    color: var(--text-secondary);
  }
}

:deep(.gray-tag) {
  background-color: var(--bg-soft) !important;
  border-color: var(--border-color) !important;
  color: var(--text-secondary) !important;
}

.operation-buttons {
  display: flex;
  justify-content: center;
  gap: var(--space-3);
  .el-button {
    margin: 0;
    padding: var(--space-1);
    font-size: var(--text-lg);
  }
}

.pg-container {
  margin-top: var(--section-padding);
  display: flex;
  justify-content: flex-end;
  :deep(.pagination-container) {
    background: transparent;
    padding: 0;
    margin: 0;
  }
}

.custom-dialog {
  :deep(.el-dialog) {
    border-radius: 12px;
    overflow: hidden;
    padding: 0;
  }
  :deep(.el-dialog__header) {
    margin: 0;
    padding: var(--section-padding) var(--space-8);
    background-color: var(--bg-soft);
    border-bottom: none;
    .el-dialog__title {
      font-size: var(--text-2xl);
      font-weight: var(--font-bold);
      color: var(--text-primary);
    }
    .el-dialog__headerbtn {
      top: var(--section-padding);
      right: var(--space-8);
      .el-dialog__close {
        font-size: var(--text-2xl);
        color: var(--text-primary);
        font-weight: var(--font-bold);
      }
    }
  }
  :deep(.el-dialog__body) {
    padding: var(--space-10) var(--space-16);
    background-color: var(--bg-soft);

    .el-form-item {
      margin-bottom: var(--space-8);
      label {
        font-size: var(--text-lg);
        font-weight: var(--font-medium);
        color: var(--text-secondary);
        &::before {
          content: none !important;
        }
      }

      &.is-required label::before {
        display: none !important;
      }
      &.is-required {
        label::before {
          content: "*" !important;
          color: var(--color-danger) !important;
          margin-right: var(--space-1) !important;
          display: inline-block !important;
        }
      }
    }

    .el-input__inner,
    .el-select .el-input__inner {
      height: 48px;
      border-radius: 8px;
      border-color: var(--border-hover);
      font-size: var(--text-lg);
    }
  }
  :deep(.el-dialog__footer) {
    padding: var(--section-padding) var(--space-8) var(--space-12);
    background-color: var(--bg-soft);
    text-align: center;
    border-top: none;

    .dialog-footer {
      display: flex;
      justify-content: center;
      gap: var(--space-10);
    }
  }
}

.dialog-save-btn {
  background-color: var(--color-action);
  border-color: var(--color-action);
  padding: var(--space-3) var(--space-16);
  font-size: var(--text-lg);
  border-radius: 8px;
  height: auto;
  &:hover {
    background-color: var(--color-action-hover);
    border-color: var(--color-action-hover);
  }
}

.dialog-cancel-btn {
  padding: var(--space-3) var(--space-16);
  font-size: var(--text-lg);
  border-radius: 8px;
  border-color: var(--text-secondary);
  color: var(--text-secondary);
  height: auto;
}

.stat-card { overflow: hidden; min-height: 112px; }
.stat-art { position: absolute; right: 0; top: 0; width: 45%; height: 100%; object-fit: cover; opacity: .45; pointer-events: none; mask-image: linear-gradient(to right, transparent, #000 65%); }
.stat-content, .stat-icon-wrapper { position: relative; z-index: 1; }
.stat-content .stat-value { font-size: 30px; }
@media(max-width:767px) { .stat-card { margin-bottom: 12px; } }
</style>
