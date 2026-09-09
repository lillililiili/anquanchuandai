<template>
  <div class="no-site">
    <h1>未授权厂站</h1>
    <p>当前账号没有可访问的厂站，无法进入业务页面。</p>
    <el-button type="primary" @click="back">返回登录</el-button>
  </div>
</template>

<script setup>
import useUserStore from '@/store/modules/user'

const router = useRouter()
const userStore = useUserStore()

function back() {
  userStore.logOut().then(() => router.replace('/login'))
}
</script>

<style scoped>
.no-site { padding: 80px 24px; text-align: center; }
.no-site h1 { margin-bottom: 12px; }
.no-site p { margin-bottom: 24px; color: var(--text-muted, #667); }
</style>
