<script setup>
import { Grid, User, Checked, VideoCamera, Microphone, Location, Warning, Document, DataAnalysis, Setting, Fold, Expand, OfficeBuilding, ArrowDown, SwitchButton, Lock, Refresh, View, Hide, Picture, Box } from '@element-plus/icons-vue'
defineProps({ name: { type: String, default: 'Grid' }, size: { type: [Number, String], default: 22 } })
const icons = { Grid, User, Checked, VideoCamera, Microphone, Location, Warning, Document, DataAnalysis, Setting, Fold, Expand, OfficeBuilding, ArrowDown, SwitchButton, Lock, Refresh, View, Hide, Picture, Box }
</script>

<template><el-icon :size="size" aria-hidden="true"><component :is="icons[name] || Document" /></el-icon></template>
