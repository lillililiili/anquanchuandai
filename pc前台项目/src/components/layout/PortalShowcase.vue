<script setup>
import { ref, watch } from 'vue';
import UiSelect from '@ui-spec/UiSelect.vue';
import UiDatePicker from '@ui-spec/UiDatePicker.vue';
import AppPanel from '@/components/ui/AppPanel.vue';
import AppButton from '@/components/ui/AppButton.vue';
import AppModal from '@/components/ui/AppModal.vue';
import { modal, openModal, closeModal } from '@/stores/modal';
const family=ref('list'), single=ref(''), multiple=ref(['a']), date=ref('2026-10-13'), dateTime=ref('2026-10-13T09:30:00'), required=ref(''), checked=ref(true), submitted=ref(false);
const options=[{value:'a',label:'维护一班'},{value:'b',label:'运行一班'},{value:'c',label:'电气一班'},{value:'d',label:'停用班组',disabled:true}];
const requiredOptions=[{value:'',label:'请选择班组'},...options];
watch(family,value=>{document.documentElement.dataset.portalFamily=value;});
</script>
<template>
  <main class="main portal-spec">
    <h1>业务画板组件验收</h1>
    <p>使用实际生产组件；数据仅存在当前页面内存，不调用业务接口。</p>
    <div class="row">
      <label>画板类型 <UiSelect v-model="family" aria-label="画板类型" :options="[['list','巡视点位 / 告警列表'],['monitor','监盘总览'],['detail','工作票 / 缺陷处理'],['sentinel','安全哨兵']]" /></label>
      <a href="/ui-spec.html">查看全部原稿组件及状态</a>
      <a href="/ui-reference/reference-3.html">查看业务画板图层重建</a>
    </div>
    <AppPanel title="列表筛选：35px">
      <div class="filters">
        <input aria-label="筛选关键词" placeholder="输入关键词">
        <UiSelect v-model="single" aria-label="筛选班组" :options="options" />
        <UiDatePicker v-model="date" aria-label="筛选日期" />
        <AppButton tone="primary" icon="search-line">查询</AppButton>
        <AppButton @click="single='';date=''">重置</AppButton>
      </div>
      <table><thead><tr><th>状态</th><th>原稿参数</th><th>操作</th></tr></thead><tbody>
        <tr><td>默认行</td><td>5ECBFF / 10% → 30% 渐变表头；CCDEFF / 5% 间隔行</td><td><AppButton tone="small">查看</AppButton></td></tr>
        <tr><td>间隔行</td><td>54.702995px 单行基准；丰富内容自然增高</td><td><AppButton tone="small" disabled>禁用</AppButton></td></tr>
        <tr class="selected"><td>选中行</td><td>沿用组件库选中态</td><td><AppButton tone="small primary">编辑</AppButton></td></tr>
      </tbody></table>
    </AppPanel>
    <AppPanel title="常规控件：32px / 紧凑操作：24px">
      <div class="row"><AppButton tone="primary">主要按钮</AppButton><AppButton>普通按钮</AppButton><AppButton tone="danger">危险操作</AppButton><AppButton disabled>禁用按钮</AppButton><AppButton tone="small">紧凑操作</AppButton><label><input v-model="checked" type="checkbox">复选框</label><label><input class="ui-switch" type="checkbox" checked>开关</label></div>
      <div class="row"><label>多选班组 <UiSelect v-model="multiple" multiple aria-label="多选班组" :options="options" /></label><label>禁用选择 <UiSelect model-value="a" aria-label="禁用选择" :options="options" disabled /></label><label>日期时间 <UiDatePicker v-model="dateTime" type="datetime-local" :step="1" aria-label="日期时间" /></label></div>
      <output aria-label="多选回显">{{ multiple.join(',') }}</output>
      <output aria-label="日期回显">{{ date }} / {{ dateTime }}</output>
    </AppPanel>
    <AppPanel title="校验、浮层与焦点恢复">
      <form @submit.prevent="submitted=true" class="row"><label>必填班组 <UiSelect v-model="required" required aria-label="必填班组" :options="requiredOptions" /></label><AppButton type="submit" tone="primary">验证必填</AppButton><span role="status">{{ submitted ? '校验通过' : '等待校验' }}</span></form>
      <AppButton v-for="(label,size) in {confirm:'确认 440px',compact:'简短表单 650px',regular:'常规表单 880px',wide:'复杂表单 1000px'}" :key="size" @click="openModal({title:'统一弹窗与内部浮层验收',size,layout:'form'})">{{ label }}</AppButton>
    </AppPanel>
    <AppModal v-if="modal.open" :title="modal.title" :size="modal.size" :layout="modal.layout"><form class="dialog-form" @submit.prevent="closeModal"><div class="dialog-form-body"><div class="dialog-grid"><label>弹窗班组<UiSelect v-model="single" aria-label="弹窗班组" :options="options" /></label><label>弹窗日期<UiDatePicker v-model="date" aria-label="弹窗日期" /></label><label class="wide">弹窗多选<UiSelect v-model="multiple" multiple aria-label="弹窗多选" :options="options" /></label><label v-for="n in (modal.size === 'wide' ? 14 : 2)" :key="n">验收字段 {{ n }}<input :placeholder="'字段 ' + n" /></label><label class="wide">备注<textarea rows="3" placeholder="整行备注" /></label></div></div><div class="dialog-form-footer"><span>检查 Escape、焦点返回及底部固定</span><AppButton @click="closeModal">取消</AppButton><AppButton type="submit" tone="primary">确认验收</AppButton></div></form></AppModal>
  </main>
</template>
<style scoped>
.portal-spec.main {margin:0 auto;max-width:1440px;padding:24px;display:grid;gap:16px;min-height:100vh}
.portal-spec h1 {margin:0;font-size:24px}.portal-spec p {margin:0;color:var(--theme-muted)}
.portal-spec .row {display:flex;gap:16px;align-items:center;flex-wrap:wrap;margin-bottom:12px}
.portal-spec label {display:inline-flex;align-items:center;gap:8px}.portal-spec table{width:100%}
.portal-spec .ui-select {width:200px}.portal-spec .ui-date {width:230px}.portal-spec output{display:block;margin-top:8px;color:var(--theme-muted)}
.portal-spec a{color:var(--theme-accent)}
</style>
