<script setup>
import VideoFrame from "@/components/domain/VideoFrame.vue";
import { helmetOf } from "@/lib/queries";
import { session } from "@/stores/session";

defineProps({
  person: { type: Object, required: true },
});
</script>

<template>
  <div
    :class="['video-thumb', person.id === session.person ? 'selected' : '']"
    data-action="select-camera"
    :data-id="person.id"
  >
    <VideoFrame :person-id="person.id" preview />
    <button type="button" class="btn plain" @click="session.person = person.id">{{ person.name }}　<small>{{ helmetOf(person.id)?.id || "未绑定" }}</small></button>
  </div>
</template>
