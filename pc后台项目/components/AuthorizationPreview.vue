<template>
  <section>
    <p class="notice">调整角色会影响所有绑定该角色的用户，请确认权限变化。</p>
    <p v-if="!preview.accounts.length">该角色当前未关联账号。保存后仍需单独分配账号。</p>
    <article v-for="account in preview.accounts" :key="account.id" class="binding-card">
      <h3>{{ account.name }}</h3><p v-if="account.noScope" class="notice warning">生效后尚未分配有效厂站范围</p><p v-if="account.lostSites.length">失去厂站：{{ account.lostSites.map(s => s.name).join('、') }}</p>
      <details v-for="[key, label] in [['added', '新增'], ['removed', '撤销'], ['retained', '保留']]" :key="key" :open="key !== 'retained'"><summary>{{ label }} {{ account[key].length }} 项</summary><ul class="permission-effects"><li v-for="item in account[key]" :key="item.key">{{ operationLabel(item.operation) }} · {{ item.siteName }}</li></ul></details>
    </article>
    <p class="muted">预览修订 {{ preview.revision }} · 权限按操作和厂站范围生效。</p>
  </section>
</template>
<script setup>
import { operationLabel } from '../operationLabels'
defineProps({ preview: { type: Object, required: true } })
</script>
<style scoped>.permission-effects { max-height: 230px; overflow: auto; padding-left: 24px; overflow-wrap: anywhere; } summary { cursor: pointer; padding: 10px 0; }</style>
