<script setup lang="ts">
import { computed } from "vue";
import { Loading } from "@element-plus/icons-vue";
import { isArray } from "@/utils/is";

/* status:'loading','error','success','empty' */
type ViewStatus = "loading" | "error" | "success" | "empty";

interface SkeletonProps<T = any> {
  // 当前视图状态
  status: ViewStatus;
  // success时传递的数据
  result: T;
  // loading时占位数据，撑起骨架
  placeholderResult: T;
  // 空数据时的文案
  emptyMsg?: string;
  // 错误时的文案
  errorMsg?: string;
  // 具体判空回调
  isEmpty?: (result: T) => boolean;
  // 不使用placeholderResult时,在原视图上覆盖 loading 的方式展示过渡效果，默认false
  coverLoading?: boolean;
  // 空内容时展示数据
  showViewInEmpty?: boolean;
}

const props = withDefaults(defineProps<SkeletonProps>(), {
  status: "loading",
  emptyMsg: "暂无数据",
  errorMsg: "未知错误",
  coverLoading: false,
  showViewInEmpty: false,
});

const emits = defineEmits(["retry"]);

const retryClick = () => {
  emits("retry");
};

const viewStatus = computed(() => {
  const status = props.status;

  if (status === "success") {
    let isEmp = false;
    const result = props.result;
    if (props.isEmpty) {
      isEmp = props.isEmpty(props.result);
    } else {
      // console.log('empty', result, !result)
      if (isArray(result)) {
        isEmp = result.length === 0;
      } else if (!result) {
        isEmp = true;
      } else {
        isEmp = false;
      }
    }
    if (isEmp) {
      return "empty";
    }
    return "success";
  }
  return status;
});

const placeholderData = computed(() => {
  if (props.result) {
    return props.result;
  }
  return props.placeholderResult;
});
</script>

<template>
  <div
    v-if="viewStatus === 'empty' && !showViewInEmpty"
    key="empty"
    class="empty_view flex-col"
  >
    <span>{{ emptyMsg }}</span>
    <el-button class="mt4 max-w-160px" @click="retryClick">重试</el-button>
  </div>

  <div
    v-else-if="viewStatus === 'error'"
    key="error"
    class="empty_view flex-col"
  >
    <span>{{ errorMsg }}</span>
    <el-button class="mt4 max-w-160px" @click="retryClick">重试</el-button>
  </div>

  <div
    v-else
    key="loadingOrContent"
    :class="[
      placeholderData && viewStatus === 'loading'
        ? 'skeleton-view-empty-view'
        : 'skeleton-view-default-view',
    ]"
  >
    <!-- 展示loading图标，只有在不是coverLoading的模式，并且placeholderData为空，并且是loading状态下 -->
    <div
      v-if="!coverLoading && !placeholderData && viewStatus === 'loading'"
      class="loading-center"
    >
      <el-icon class="is-loading" size="40"><Loading /></el-icon>
    </div>

    <!-- 展示 spin，在状态为loading时，且placeholderData为空时 -->
    <div
      v-else
      v-loading="viewStatus === 'loading' && !placeholderData"
      class="skeleton-content-view"
    >
      <slot
        :data="placeholderData"
        :mask="viewStatus === 'loading' ? 'skeleton-mask' : ''"
        :status="viewStatus"
        :success="viewStatus === 'success'"
      ></slot>
    </div>
  </div>
</template>

<style>
.clam-box {
  width: 100%;
  height: 100%;
}
.empty_view {
  padding-top: 50px;
  padding-bottom: 50px;
  align-items: center;
}
.empty_img {
  width: 310px;
  height: 218px;
}
.trip_text {
  font-size: 20px;
  color: var(--text-muted);
}

.mt4 {
  margin-top: 4px;
}

.flex-col {
  display: flex;
  flex-direction: column;
}

.loading-center {
  padding: 20px;
  display: flex;
  justify-content: center;
  align-items: center;
}

.skeleton-content-view {
  width: 100%;
  height: 100%;
}

.skeleton-view-default-view span,
.skeleton-view-default-view a,
.skeleton-view-default-view img,
.skeleton-view-default-view td,
.skeleton-view-default-view input,
.skeleton-view-default-view button {
  /* 骨架屏过渡简化，移除不必要的 width 动画 */
  transition-duration: 0.3s;
  transition-timing-function: ease-out;
  transition-property: background;
}

.skeleton-view-empty-view {
  position: relative;
  pointer-events: none;
}

.skeleton-view-empty-view::before {
  content: " ";
  position: absolute;
  width: 100%;
  height: 100%;
  top: 0;
  left: 0;
  background: var(--bg-soft);
  animation: loading 1.4s ease-in-out infinite;
  z-index: 1;
}

@keyframes loading {
  0%, 100% { opacity: 0.42; }
  50% { opacity: 0.78; }
}

.skeleton-view-empty-view .skeleton-mask {
  position: relative;
}
.skeleton-view-empty-view .skeleton-mask::before {
  content: " ";
  background-color: var(--bg-soft);
  position: absolute;
  width: 100%;
  height: 100%;
  border: 1px solid var(--bg-soft);
  top: -1px;
  left: -1px;
  z-index: 1;
}

.skeleton-view-empty-view button,
.skeleton-view-empty-view span,
.skeleton-view-empty-view input,
.skeleton-view-empty-view td,
.skeleton-view-empty-view a {
  color: rgba(0, 0, 0, 0) !important;
  border: none;
  background: var(--bg-soft) !important;
}
/* [src=""],img:not([src])*/
.skeleton-view-empty-view img {
  content: url(./no_url.png);
  border-radius: 2px;
  background: var(--bg-soft) !important;
}
</style>
