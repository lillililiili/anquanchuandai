<script setup>
defineProps({
  title: { type: String, default: "" },
  extraClass: { type: String, default: "" },
});
</script>

<template>
  <section :class="['panel', extraClass]">
    <div class="panel-heading">
      <h2><slot name="title">{{ title }}</slot></h2>
      <div><slot name="extra" /></div>
    </div>
    <div class="panel-body"><slot /></div>
  </section>
</template>
