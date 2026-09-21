<template>
  <form class="master-form" novalidate @submit.prevent="submit">
    <p class="notice">仅保存到当前页面，刷新恢复初始演示数据。{{ entity === 'accounts' ? '不设置真实密码；账号创建后再分配授权。' : '' }}</p>
    <div v-if="error || Object.keys(localErrors).length" ref="errorBox" class="notice error" role="alert" tabindex="-1">
      <strong>未保存，请检查以下内容</strong><p v-if="error">{{ error.message }} <small>{{ error.errorCode }} · {{ error.requestId }}</small></p>
      <ul><li v-for="(message, key) in errors" :key="key"><a :href="'#field-' + key" @click.prevent="focusField(key)">{{ message }}</a></li></ul>
      <ul v-if="error?.impacts"><li v-for="item in error.impacts" :key="item.label + item.id">{{ item.label }}：{{ item.name }}</li></ul>
    </div>
    <div class="form-grid">
      <label v-if="!['accounts', 'roles', 'dutyShifts'].includes(entity)"><span class="field-label">编号<span class="required-mark" aria-hidden="true">*</span></span><input id="field-code" aria-required="true" v-model="form.code" maxlength="50" :aria-invalid="!!errors.code" aria-describedby="error-code" /><small id="error-code" class="error">{{ errors.code }}</small></label>
      <label v-if="entity === 'accounts'"><span class="field-label">登录名<span class="required-mark" aria-hidden="true">*</span></span><input id="field-loginName" aria-required="true" v-model="form.loginName" maxlength="50" :disabled="!!record" :aria-invalid="!!errors.loginName" aria-describedby="error-loginName" /><small id="error-loginName" class="error">{{ errors.loginName }}</small></label>
      <label><span class="field-label">名称 / 姓名<span class="required-mark" aria-hidden="true">*</span></span><input id="field-name" aria-required="true" v-model="form.name" aria-label="名称 / 姓名" maxlength="100" :aria-invalid="!!errors.name" aria-describedby="error-name" /><small id="error-name" class="error">{{ errors.name }}</small></label>
      <label v-if="entity === 'sites'">厂站时区<input id="field-timezone" v-model="form.timezone" list="timezones" aria-describedby="error-timezone" /><datalist id="timezones"><option>Asia/Shanghai</option><option>UTC</option><option>America/New_York</option></datalist><small id="error-timezone" class="error">{{ errors.timezone }}</small></label>
      <label v-if="['organizations', 'areas'].includes(entity)">上级节点<select id="field-parentId" v-model="form.parentId"><option value="">根节点</option><option v-for="o in options[entity]?.filter(x => x.id !== record?.id)" :key="o.id" :value="o.id">{{ o.name }}</option></select><small id="error-parentId" class="error">{{ errors.parentId }}</small></label>
      <label v-if="entity === 'people'">组织 / 班组<select id="field-organizationId" v-model="form.organizationId"><option value="">尚未关联</option><option v-for="o in options.organizations" :key="o.id" :value="o.id">{{ o.name }}</option></select><small class="error">{{ errors.organizationId }}</small></label>
      <label v-if="['people', 'organizations'].includes(entity)">所属 / 关联区域<select id="field-areaId" v-model="form.areaId"><option value="">尚未关联（不代表全厂授权）</option><option v-for="o in options.areas" :key="o.id" :value="o.id">{{ o.name }}</option></select><small class="error">{{ errors.areaId }}</small></label>
      <label v-if="entity === 'people'" class="wide">备注<textarea id="field-remark" v-model="form.remark" maxlength="500" rows="3" /><small class="error">{{ errors.remark }}</small></label>
      <label v-if="entity === 'accounts'" class="wide">关联人员（可不关联）<select id="field-personId" v-model="form.personId"><option value="">不关联人员</option><option v-for="p in options.people" :key="p.id" :value="p.id">{{ p.name }} · {{ p.code }}{{ p.accountId && p.accountId !== record?.id ? '（已关联其他账号）' : '' }}</option></select><small class="error">{{ errors.personId }}</small></label>
    </div>
    <template v-if="entity === 'dutyShifts'">
      <p class="notice">输入时区：{{ timezone }}，内部保存UTC。仅未来班次可维护。</p>
      <div class="form-grid"><label>开始时间<input id="field-startsAt" v-model="form.localStart" type="datetime-local" /><small class="error">{{ errors.startsAt }}</small></label><label>结束时间<input id="field-endsAt" v-model="form.localEnd" type="datetime-local" /><small class="error">{{ errors.endsAt }}</small></label></div>
      <fieldset id="field-personIds"><legend>班次成员 · 已选 {{ form.personIds.length }} 人</legend><input v-model="memberKeyword" aria-label="搜索班次成员" placeholder="搜索编号或姓名" /><div class="choice-grid"><label v-for="p in options.people?.filter(p => (p.name + p.code).includes(memberKeyword))" :key="p.id"><input v-model="form.personIds" type="checkbox" :value="p.id" />{{ p.name }} · {{ p.code }}</label></div><small class="error">{{ errors.personIds }}</small></fieldset>
    </template>
    <template v-if="entity === 'accounts' && record">
      <h3 id="field-bindings" tabindex="-1">角色与范围</h3><p class="muted">每条角色的操作与范围独立计算。不选择角色即无授权。</p>
      <section v-for="(binding, index) in form.bindings" :key="index" class="binding-card">
        <div class="form-grid"><label>角色<select v-model="binding.roleId"><option value="">请选择</option><option v-for="r in assignableRoles" :key="r.id" :value="r.id">{{ r.name }}</option></select></label><label>厂站范围（Ctrl / ⌘ 多选）<select v-model="binding.siteIds" multiple><option v-for="s in options.sites" :key="s.id" :value="s.id">{{ s.name }}</option></select></label></div>
        <label class="inline-check"><input v-model="binding.allAreas" type="checkbox" />所选厂站全部区域</label>
        <label v-if="!binding.allAreas">限定区域<select v-model="binding.areaIds" multiple><option v-for="a in options.scopeAreas?.filter(a => binding.siteIds.includes(a.siteId))" :key="a.id" :value="a.id">{{ a.name }} · {{ a.siteId }}</option></select></label>
        <button class="button danger" type="button" @click="form.bindings.splice(index, 1)">移除此角色</button>
      </section>
      <small class="error">{{ errors.bindings }}</small><button class="button" type="button" @click="form.bindings.push({ roleId: '', siteIds: [siteId], allAreas: true, areaIds: [] })">添加角色范围</button>
    </template>
    <template v-if="entity === 'roles'">
      <fieldset id="field-operations"><legend>允许操作</legend><div class="choice-grid"><label v-for="op in OPERATIONS.filter(item => !item.startsWith('integrations:'))" :key="op"><input v-model="form.operations" type="checkbox" :value="op" />{{ operationNames[op] || op }}</label></div><small class="error">{{ errors.operations }}</small></fieldset>
      <label id="field-siteIds">厂站范围<select v-model="form.siteIds" multiple><option v-for="s in options.sites" :key="s.id" :value="s.id">{{ s.name }}</option></select><small class="error">{{ errors.siteIds }}</small></label>
      <label class="inline-check"><input v-model="form.allAreas" type="checkbox" />所选厂站全部区域</label>
      <label v-if="!form.allAreas" id="field-areaIds">限定区域<select v-model="form.areaIds" multiple><option v-for="a in options.scopeAreas?.filter(a => form.siteIds.includes(a.siteId))" :key="a.id" :value="a.id">{{ a.name }} · {{ a.siteId }}</option></select><small class="error">{{ errors.areaIds }}</small></label>
    </template>
    <div class="form-footer"><span class="muted">{{ record ? '版本 ' + record.version : '新记录' }} · 演示数据</span><button class="button" type="button" :disabled="busy" @click="$emit('close')">取消</button><button class="button primary" type="submit" :disabled="busy">{{ busy ? '正在保存…' : '保存本地记录' }}</button></div>
  </form>
</template>
<script setup>
import { computed, nextTick, ref, watch } from 'vue'
import { OPERATIONS, DELEGATE_ROLES } from '../access'
import { localTime, toUtc } from '../time'
const props = defineProps({ entity: String, record: Object, options: Object, siteId: String, timezone: String, busy: Boolean, error: Object, isSystem: Boolean })
const emit = defineEmits(['save', 'close', 'dirty'])
const r = props.record ? JSON.parse(JSON.stringify(props.record)) : {}, grant = r.grants?.[0]
if (props.entity === 'accounts') {
  r.roleScopes ||= {}
  for (const id of r.roleIds || []) if (!r.roleScopes[id]) { const g = props.options.roles.find(role => role.id === id)?.grants?.[0]; if (g) r.roleScopes[id] = { siteIds: g.siteIds, areaIds: g.areaIds } }
}
const form = ref({ code: r.code || '', name: r.name || '', loginName: r.loginName || '', timezone: r.timezone || 'Asia/Shanghai', parentId: r.parentId || '', areaId: r.areaId || '', organizationId: r.organizationId || '', remark: r.remark || '', personId: r.personId || '', personIds: [...(r.personIds || [])], localStart: localTime(r.startsAt, props.timezone), localEnd: localTime(r.endsAt, props.timezone), operations: [...(grant?.operations || [])], siteIds: [...(grant?.siteIds || [props.siteId])], allAreas: !grant || grant.areaIds === '*', areaIds: Array.isArray(grant?.areaIds) ? [...grant.areaIds] : [], bindings: (r.roleIds || []).map(roleId => ({ roleId, siteIds: [...(r.roleScopes?.[roleId]?.siteIds || [props.siteId])], allAreas: r.roleScopes?.[roleId]?.areaIds === '*' || !r.roleScopes?.[roleId], areaIds: Array.isArray(r.roleScopes?.[roleId]?.areaIds) ? [...r.roleScopes[roleId].areaIds] : [] })) })
const initial = JSON.stringify(form.value), memberKeyword = ref(''), localErrors = ref({}), errorBox = ref(null)
const errors = computed(() => ({ ...props.error?.fields, ...localErrors.value }))
const assignableRoles = computed(() => props.options.roles?.filter(r => r.id !== 'system' && (props.isSystem || DELEGATE_ROLES.includes(r.id))) || [])
const operationNames = { 'overview:read': '工作台查看', 'people:read': '人员查看', 'people:write': '人员维护', 'organization:read': '组织区域查看', 'organization:write': '组织区域维护', 'sites:read': '厂站查看', 'sites:write': '厂站维护（仅系统身份执行）', 'duty:read': '名册查看', 'duty:write': '名册维护', 'access:read': '账号角色查看', 'accounts:write': '账号维护与有限委派', 'roles:write': '角色维护（仅系统身份执行）', 'assets:read': '资产查看', 'assets:write': '资产办理', 'audit:read': '操作日志查看', 'integrations:read': '接入配置查看', 'groups:write': '常设协助组维护' }
watch(form, () => emit('dirty', JSON.stringify(form.value) !== initial), { deep: true })
watch(() => props.error, async e => { if (e) { await nextTick(); errorBox.value?.focus() } })
function focusField(key) { const el = document.getElementById('field-' + key); (el?.matches('input, select, textarea') ? el : el?.querySelector('input, select, textarea') || el)?.focus() }
async function submit() {
  localErrors.value = {}
  const data = JSON.parse(JSON.stringify(form.value))
  if (!data.name.trim()) localErrors.value.name = '请填写名称 / 姓名'
  if (!['accounts', 'roles', 'dutyShifts'].includes(props.entity) && !data.code.trim()) localErrors.value.code = '请填写编号'
  if (props.entity === 'accounts' && !data.loginName.trim()) localErrors.value.loginName = '请填写登录名'
  if (props.entity === 'dutyShifts') {
    for (const [field, key] of [['startsAt', 'localStart'], ['endsAt', 'localEnd']]) { try { data[field] = toUtc(data[key], props.timezone) } catch (e) { localErrors.value[field] = e.message } }
  }
  if (Object.keys(localErrors.value).length) { await nextTick(); errorBox.value?.focus(); return }
  if (props.entity === 'roles') data.areaIds = data.allAreas ? '*' : data.areaIds
  data.bindings = data.bindings.map(b => ({ roleId: b.roleId, siteIds: b.siteIds, areaIds: b.allAreas ? '*' : b.areaIds }))
  emit('save', data)
}
</script>
