<template>
  <section class="verification-review">
    <h3>平台核验与复核</h3>
    <el-descriptions :column="1" border>
      <el-descriptions-item label="现场上报">{{ verificationStepLabel(event.fieldReportStatus) }}</el-descriptions-item>
      <el-descriptions-item label="核验结果">{{ verificationStepLabel(event.verificationStatus) }}</el-descriptions-item>
      <el-descriptions-item label="管理员复核">{{ verificationStepLabel(event.reviewStatus) }}</el-descriptions-item>
      <el-descriptions-item label="外部结案">未同步</el-descriptions-item>
    </el-descriptions>
    <p>平台核验不代表正式结案，正式结案由原安监系统确认。</p>
    <p v-if="event.status === 'closed'">历史已处理记录，不能据此推定已核验或已结案。</p>
    <template v-if="event.status === 'pending_review'">
      <p>{{ reviewActorHint(event) }}</p>
      <p>核验说明及操作人见下方动作时间线。</p>
      <div v-if="mediaError" role="alert">附件加载失败，请刷新详情后再审批。</div>
      <div v-for="item in media" :key="item.id">
        <el-button link type="primary" @click="downloadMedia(item)">{{ item.mediaType?.startsWith('video/') ? '查看现场视频' : '查看现场照片' }} · {{ item.id }}</el-button>
      </div>
      <p v-if="!mediaLoading && !mediaError && !media.length">暂无已提交附件</p>
      <template v-if="eligible">
        <el-input v-model="reason" type="textarea" maxlength="500" show-word-limit placeholder="填写审批意见" :disabled="submitting" />
        <el-button class="review-submit" type="primary" :loading="submitting" :disabled="!reason.trim() || mediaLoading || !!mediaError" @click="submit">审批通过 · 完成核验</el-button>
      </template>
      <p v-else>等待有权限且符合上述规则的管理员审批。</p>
      <p v-if="error" role="alert">{{ error }}</p>
    </template>
  </section>
</template>

<script setup>
import { computed, ref, watch, onBeforeUnmount } from 'vue'
import useUserStore from '@/store/modules/user'
import { reviewEvent, listEventMedia, fetchEventMedia } from '@/api/wear/events'
import { canReviewVerification, reviewActorHint, verificationStepLabel } from '@/api/wear/eventWorkflow'
const props = defineProps({ event: { type: Object, required: true }, actions: { type: Array, default: () => [] } })
const emit = defineEmits(['reviewed'])
const actor = useUserStore()
const eligible = computed(() => canReviewVerification(props.event, actor, props.actions))
const reason = ref(''), error = ref(''), submitting = ref(false)
const media = ref([]), mediaError = ref(''), mediaLoading = ref(false)
let generation = 0
watch(() => [props.event.id, props.event.version], async () => {
  const current = ++generation
  reason.value = ''; error.value = ''; media.value = []; mediaError.value = ''
  mediaLoading.value = false
  if (!props.event.id || props.event.status !== 'pending_review') return
  mediaLoading.value = true
  try {
    const response = await listEventMedia(props.event.id)
    if (current === generation) media.value = response.data || []
  } catch { if (current === generation) mediaError.value = '附件加载失败' }
  finally { if (current === generation) mediaLoading.value = false }
}, { immediate: true })
onBeforeUnmount(() => { generation++ })
async function downloadMedia(item) {
  try {
    const blob = await fetchEventMedia(props.event.id, item.id)
    if (!(blob instanceof Blob) || !/^(image|video)\//.test(blob.type)) throw new Error('无效附件响应')
    const url = URL.createObjectURL(blob)
    const anchor = document.createElement('a')
    const extension = { 'video/mp4': 'mp4', 'video/webm': 'webm', 'image/png': 'png', 'image/jpeg': 'jpg' }[item.mediaType] || 'bin'
    anchor.href = url; anchor.download = `${item.id}.${extension}`
    anchor.click(); setTimeout(() => URL.revokeObjectURL(url), 1000)
  } catch { error.value = '附件获取失败，请重试' }
}
async function submit() {
  if (submitting.value || !eligible.value || !reason.value.trim() || mediaLoading.value || mediaError.value) return
  submitting.value = true; error.value = ''
  const id = props.event.id
  try {
    await reviewEvent(id, { reason: reason.value.trim(), version: props.event.version })
    emit('reviewed', id)
  } catch (e) { error.value = e?.message || '审批失败，请刷新后重试' }
  finally { submitting.value = false }
}
</script>
<style scoped>
.verification-review { margin: 20px 0; }
.verification-review p { color: var(--el-text-color-secondary); font-size: 13px; }
.review-submit { margin-top: 12px; }
</style>
