<script setup>
import VideoFrame from "@/components/domain/VideoFrame.vue";
import { helmetOf } from "@/lib/queries";
import { session } from "@/stores/session";

defineProps({
  person: { type: Object, required: true },
});
</script>

<template>
  <button
    type="button"
    :class="['video-thumb', person.id === session.person ? 'selected' : '']"
    data-action="select-camera"
    :data-id="person.id"
    @click="session.person = person.id"
  >
    <VideoFrame :person-id="person.id" />
    <strong>{{ person.name }}　<small>{{ helmetOf(person.id)?.id || "未绑定" }}</small></strong>
    <small>{{ person.area }}</small>
  </button>
</template>
