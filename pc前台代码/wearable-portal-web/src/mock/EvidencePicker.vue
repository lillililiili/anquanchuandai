<script setup>
import { reactive, ref, watch } from 'vue'
import { getMaterials } from '@/api/spatial'
import { usePortalQuery } from '@/composables/usePortalQuery'
const props = defineProps({ siteId: String })
const emit = defineEmits(['select'])
const query = reactive(usePortalQuery()), keyword = ref(''), page = ref(1), selected = ref('')
function load() { selected.value = ''; emit('select', null); query.run(signal => getMaterials({ siteId: props.siteId, keyword: keyword.value, pageNum: String(page.value), pageSize: '10' }, signal)) }
watch(() => props.siteId, load, { immediate: true })
</script>
<template><section aria-label="资料证据选择器"><label>资料关键词<input v-model="keyword" maxlength="100" /></label><el-button @click="page = 1; load()">检索证据资料</el-button><p>与现场资料共用查询；引用冻结标识、版本、摘要及时间，不代表已提交核验。</p><p v-if="query.error" role="alert">{{ query.error.message }}</p><p v-if="query.state === 'LOADING'" role="status">正在读取资料…</p><label v-for="item in query.data?.items" :key="item.id" class="evidence-choice"><input v-model="selected" type="radio" name="material-evidence" :value="item.id" @change="emit('select', item)" />{{ item.name }} · 版本{{ item.version }} · {{ item.source === 'BROWSER_MEMORY' ? '内存文件' : '仅元数据' }}</label><AppPagination v-if="query.data?.total" :current-page="page" :page-size="10" :total="query.data.total" @current-change="n => { page = n; load() }" /></section></template>
<style scoped>.evidence-choice { display: flex; align-items: center; gap: 10px; padding: 8px 0; overflow-wrap: anywhere; }.evidence-choice input { width: auto; }</style>
