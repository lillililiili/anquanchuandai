<script setup>
import PageHeading from "./PageHeading.vue";
import AppEmpty from "@/components/ui/AppEmpty.vue";
</script>

<template>
  <PageHeading title="暂无记录" />
  <AppEmpty text="当前厂站没有对应记录" />
  <a class="btn" href="#/overview">返回综合总览</a>
</template>
