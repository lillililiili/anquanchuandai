<script setup>
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import BrandMark from '@/components/BrandMark.vue'
const route = useRoute()
const forbidden = computed(() => route.meta.status === 401)
</script>

<template>
  <main class="error-page"><BrandMark /><span class="error-code">{{ forbidden ? '401' : '404' }}</span><h1>{{ forbidden ? '访问受限' : '页面未找到' }}</h1><p>{{ forbidden ? '当前账号没有访问此页面的权限，请联系管理员。' : '页面地址可能已变更，请返回工作空间继续操作。' }}</p><div class="error-actions"><router-link class="primary-link" to="/overview">返回安全总览</router-link><router-link to="/login">前往登录</router-link></div></main>
</template>
