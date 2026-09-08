<template>
  <Teleport to="body">
    <TransitionGroup name="alarm-slide" tag="div" class="alarm-container">
      <div
        v-for="alarm in alarmList"
        :key="alarm.id"
        class="alarm-toast"
        @click="handleClick(alarm)"
      >
        <div class="alarm-toast-icon">
          <el-icon><WarningFilled /></el-icon>
        </div>
        <div class="alarm-toast-content">
          <div class="alarm-toast-type">{{ alarm.type }}</div>
          <div class="alarm-toast-user">{{ alarm.user }}{{ alarm.device ? ` · ${alarm.device}` : '' }}</div>
        </div>
        <div class="alarm-toast-detail">详情</div>
      </div>
    </TransitionGroup>
  </Teleport>
</template>

<script setup>
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { WarningFilled } from '@element-plus/icons-vue'

const router = useRouter()
const alarmList = ref([])
let alarmIdCounter = 0

// 显示告警通知
function show(alarmData) {
  const alarmType = alarmData.alarmType || '告警'
  const userName = alarmData.userName || '未知'
  const hatNumber = alarmData.hatNumber || ''

  const alarm = {
    id: ++alarmIdCounter,
    type: alarmType,
    user: userName,
    device: hatNumber,
    data: alarmData
  }

  alarmList.value.push(alarm)

  // 10秒后自动关闭
  setTimeout(() => {
    remove(alarm.id)
  }, 10000)
}

// 移除指定告警
function remove(id) {
  const index = alarmList.value.findIndex(a => a.id === id)
  if (index > -1) {
    alarmList.value.splice(index, 1)
  }
}

// 点击处理
function handleClick(alarm) {
  remove(alarm.id)
  router.push({
    path: '/sos',
    query: {
      showDetail: 'true',
      alarmData: JSON.stringify(alarm.data)
    }
  })
}

// 暴露方法
defineExpose({ show, remove })
</script>

<style scoped>
.alarm-container {
  position: fixed;
  top: 20px;
  right: 20px;
  z-index: 9999;
  display: flex;
  flex-direction: column;
  gap: 10px;
  pointer-events: none;
}

.alarm-toast {
  display: flex;
  align-items: center;
  gap: 8px;
  width: 300px;
  padding: 14px;
  border: 1px solid rgba(224, 99, 99, 0.42);
  border-radius: 10px;
  background: #9f3636;
  box-shadow: 0 14px 38px rgba(61, 15, 15, 0.32);
  cursor: pointer;
  pointer-events: auto;
}

.alarm-toast-icon {
  width: 26px;
  height: 26px;
  background: rgba(255, 255, 255, 0.15);
  border-radius: 7px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.alarm-toast-icon .el-icon {
  font-size: 15px;
  color: #fff;
}

.alarm-toast-content {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
}

.alarm-toast-type {
  color: #fff;
  font-size: 13px;
  font-weight: 600;
  line-height: 1.3;
}

.alarm-toast-user {
  color: rgba(255, 255, 255, 0.85);
  font-size: 11px;
  line-height: 1.3;
}

.alarm-toast-detail {
  align-self: flex-end;
  padding: 3px 8px;
  background: rgba(255, 255, 255, 0.15);
  border-radius: 6px;
  color: rgba(255, 255, 255, 0.9);
  font-size: 11px;
  font-weight: 500;
  white-space: nowrap;
}

/* 动画 */
.alarm-slide-enter-active,
.alarm-slide-leave-active {
  transition: all 0.3s ease;
}

.alarm-slide-enter-from {
  opacity: 0;
  transform: translateX(100%);
}

.alarm-slide-leave-to {
  opacity: 0;
  transform: translateX(100%);
}
</style>
