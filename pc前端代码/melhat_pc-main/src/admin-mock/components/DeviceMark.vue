<template><figure class="device-mark"><img :src="pictures[type] || pictures.HELMET" :alt="name + '概念示意图，非确认型号'" width="256" height="256" loading="lazy" /><figcaption>{{ name }} · 装备示意</figcaption></figure></template>
<script setup>
import { computed } from 'vue'
import { DEVICE_TYPES } from '../deviceData'
import helmet from '../assets/visual/helmet.webp'
import harness from '../assets/visual/harness.webp'
import watch from '../assets/visual/watch.webp'
const props = defineProps({ type: String })
const pictures = { HELMET: helmet, BELT: harness, WATCH: watch }
const name = computed(() => DEVICE_TYPES[props.type] || '设备')
</script>
