<script setup>
import AppModal from '../../src/components/ui/AppModal.vue'
import AppButton from '../../src/components/ui/AppButton.vue'
import GroupForm from '../../src/views/dispatch/GroupForm.vue'
import InviteForm from '../../src/views/dispatch/InviteForm.vue'
import FenceMembersModal from '../../src/views/fences/FenceMembersModal.vue'
import FenceRecordsModal from '../../src/views/fences/FenceRecordsModal.vue'
import { modal, modalView, modalProps, modalFooter, openModal } from '../../src/stores/modal'
import { session } from '../../src/stores/session'
import { confirm } from '../../src/lib/dialogs'
import { db, tick, failSave } from '@/mock/runtime'
session.fenceDraft = { members: ['P1'] }
</script>
<template>
  <main style="padding:32px"><h1>前台弹窗隔离验收</h1><p>使用实际业务组件；数据只在内存中，接口已隔离。</p>
    <div class="row" style="gap:12px;margin:24px 0">
      <AppButton @click="openModal({title:'新建协助分组',layout:'form',view:GroupForm})">新建分组</AppButton>
      <AppButton @click="openModal({title:'编辑协助分组',layout:'form',view:GroupForm,props:{groupId:'G1'}})">编辑分组</AppButton>
      <AppButton @click="openModal({title:'邀请成员',layout:'form',size:'compact',view:InviteForm,props:{callId:db.state.calls[0]?.id}})">邀请成员</AppButton>
      <AppButton @click="openModal({title:'选择围栏适用人员',layout:'form',view:FenceMembersModal})">选择成员</AppButton>
      <AppButton @click="openModal({title:'围栏进出记录',wide:true,layout:'form',view:FenceRecordsModal})">查看记录</AppButton>
      <AppButton @click="confirm('删除确认','仅验证布局与取消，不删除任何记录',()=>{})">删除确认</AppButton>
    </div><label><input type="checkbox" v-model="failSave">模拟保存失败</label>
    <p aria-live="polite">已保存分组：{{ (tick, db.state.groups.map(g=>g.name).join('、')) }}</p>
    <p>已选围栏成员：{{ session.fenceDraft.members.join('、') }}</p>
    <AppModal v-if="modal.open" :title="modal.title" :size="modal.size" :wide="modal.wide" :layout="modal.layout" :tone="modal.tone"><component :is="modalView" v-bind="modalProps" /><template v-if="modalFooter" #footer><component :is="modalFooter" v-bind="modalProps" /></template></AppModal>
  </main>
</template>
