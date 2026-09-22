<template>
  <section>
    <p class="notice">仅本后台权限预览，不改变监护前台授权。确认前重新检查版本与范围；不同角色的操作和区域不会交叉拼接。</p>
    <p v-if="!preview.accounts.length">该角色当前未关联账号。保存后仍需单独分配账号。</p>
    <article v-for="account in preview.accounts" :key="account.id" class="binding-card">
      <h3>{{ account.name }}</h3><p v-if="account.noScope" class="notice warning">生效后尚未分配有效厂站范围</p><p v-if="account.lostSites.length">失去厂站：{{ account.lostSites.map(s => s.name).join('、') }}</p>
      <details v-for="[key, label] in [['added', '新增'], ['removed', '撤销'], ['retained', '保留']]" :key="key" :open="key !== 'retained'"><summary>{{ label }} {{ account[key].length }} 项</summary><ul class="permission-effects"><li v-for="item in account[key]" :key="item.key">{{ item.operation }} · {{ item.siteName }} / {{ item.areaName }}</li></ul></details>
    </article>
    <p class="muted">预览修订 {{ preview.revision }} · 全厂项包含未指定区域及未来区域，各已建区域同时列示以便核对。</p>
  </section>
</template>
<script setup>
defineProps({ preview: { type: Object, required: true } })
</script>
<style scoped>.permission-effects { max-height: 230px; overflow: auto; padding-left: 24px; overflow-wrap: anywhere; } summary { cursor: pointer; padding: 10px 0; }</style>
