<script setup>
defineProps({
  text: { type: String, default: "" },
});
</script>

<template>
  <p>{{ text }}</p>
  <p class="note">当前浏览器未提供语音合成，可预览广播文字。</p>
</template>
