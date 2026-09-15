<template>
  <el-dialog :model-value="modelValue" title="批量导入" width="640px" destroy-on-close @close="close">
    <el-alert title="仅支持 .xlsx，最多 5,000 行。系统会先校验全部数据；任一行有误时不会写入。" type="info" :closable="false" show-icon />
    <div class="import-actions">
      <el-upload ref="uploadRef" drag :auto-upload="false" :limit="1" accept=".xlsx" :on-change="onFile" :on-remove="onRemove">
        <el-icon class="el-icon--upload"><UploadFilled /></el-icon>
        <div class="el-upload__text">拖入 Excel 文件，或<em>点击选择</em></div>
        <template #tip><div class="el-upload__tip">请使用最新模板，避免字段名称或格式不一致。</div></template>
      </el-upload>
      <div class="import-options">
        <el-switch v-model="updateExisting" />
        <span>更新已存在数据（默认关闭）</span>
        <el-button link type="primary" icon="Download" @click="template">下载导入模板</el-button>
      </div>
    </div>
    <el-result v-if="result && !result.errors?.length" icon="success" title="导入完成" :sub-title="`共 ${result.total} 行，新建 ${result.created}，更新 ${result.updated}，跳过 ${result.skipped}`" />
    <div v-else-if="result?.errors?.length" class="error-result">
      <el-alert :title="`发现 ${result.errors.length} 项错误，本次未写入任何数据`" type="error" :closable="false" show-icon />
      <el-table :data="result.errors" max-height="260" size="small">
        <el-table-column label="行号" prop="row" width="80" />
        <el-table-column label="字段" prop="field" width="140" />
        <el-table-column label="原因" prop="reason" min-width="260" />
      </el-table>
      <el-button class="download-errors" icon="Download" @click="downloadErrors">下载错误明细</el-button>
    </div>
    <template #footer>
      <el-button @click="close">关闭</el-button>
      <el-button type="primary" :loading="submitting" :disabled="!file" @click="submit">开始导入</el-button>
    </template>
  </el-dialog>
</template>

<script setup>
import { importResource, downloadImportTemplate } from '@/api/wear/admin'
import { saveAs } from 'file-saver'

const props = defineProps({
  modelValue: { type: Boolean, default: false },
  resource: { type: String, required: true },
  templateName: { type: String, default: '导入模板.xlsx' }
})
const emit = defineEmits(['update:modelValue', 'success'])
const uploadRef = ref()
const file = ref(null)
const updateExisting = ref(false)
const submitting = ref(false)
const result = ref(null)

function onFile(uploadFile) {
  const raw = uploadFile.raw
  if (!raw?.name?.toLowerCase().endsWith('.xlsx')) {
    ElMessage.error('仅支持 .xlsx 文件')
    uploadRef.value?.clearFiles()
    file.value = null
    return
  }
  file.value = raw
  result.value = null
}
function onRemove() { file.value = null; result.value = null }
function template() { downloadImportTemplate(props.resource, props.templateName) }
function close() {
  if (submitting.value) return
  emit('update:modelValue', false)
  uploadRef.value?.clearFiles()
  file.value = null
  result.value = null
  updateExisting.value = false
}
function submit() {
  if (!file.value) return
  submitting.value = true
  importResource(props.resource, file.value, updateExisting.value)
    .then(res => {
      result.value = res?.data || res || {}
      if (!result.value.errors?.length) {
        ElMessage.success('导入完成')
        emit('success', result.value)
      }
    })
    .finally(() => { submitting.value = false })
}
function downloadErrors() {
  const escape = value => `"${String(value ?? '').replaceAll('"', '""')}"`
  const lines = [['行号', '字段', '原因'], ...result.value.errors.map(item => [item.row, item.field, item.reason])]
  const content = '\ufeff' + lines.map(row => row.map(escape).join(',')).join('\r\n')
  saveAs(new Blob([content], { type: 'text/csv;charset=utf-8' }), '导入错误明细.csv')
}
</script>

<style scoped>
.import-actions { margin-top: 16px; }
.import-options { display: flex; align-items: center; gap: 10px; margin-top: 12px; color: var(--el-text-color-regular); }
.import-options .el-button { margin-left: auto; }
.error-result { margin-top: 16px; }
.error-result .el-table { margin-top: 12px; }
.download-errors { margin-top: 12px; }
</style>
