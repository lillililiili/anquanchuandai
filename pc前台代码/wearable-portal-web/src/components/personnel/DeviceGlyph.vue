<script setup>
defineProps({ type: { type: String, required: true } })
</script>
<template>
  <svg class="device-glyph" viewBox="0 0 48 48" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
    <g v-if="type === 'helmet'"><path d="M8 31v-8a16 16 0 0 1 32 0v8M5 31h38v6H5zM20 8v15M28 8v15M12 37v4h24v-4" /></g>
    <g v-else-if="type === 'belt'"><path d="m12 5-5 24 8 14 9-18L33 43l8-14-5-24h-7l-5 16-5-16zM9 25h30M16 5l8 20L32 5" /><rect x="19" y="22" width="10" height="8" rx="2" /></g>
    <g v-else><rect x="13" y="13" width="22" height="22" rx="6" /><path d="m17 13 2-10h10l2 10M17 35l2 10h10l2-10M24 19v6l5 3M35 21h3" /></g>
  </svg>
</template>

