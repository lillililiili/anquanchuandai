<script setup>
import { onUnmounted, ref, watch } from 'vue';
import { createLiveVideoPlayer } from '@/lib/live-video-player';
const props=defineProps({live:{type:Object,required:true},label:{type:String,default:'安全帽实时视频'}});
const video=ref(null),state=ref('loading'),error=ref(''),fallback=ref(false);
let player, element;
function play(){void player?.retry();}
function useHls(){void player?.useHls();}
function mediaError(){player?.mediaError();}
watch(()=>[props.live,props.live.url,props.live.protocol,props.live.streamId,props.live.hlsUrl,props.live.expiresAt,video.value],()=>{
  if(element!==video.value){player?.dispose();element=video.value;player=element?createLiveVideoPlayer(element,{onChange:value=>{state.value=value.state;error.value=value.error;fallback.value=value.fallback;}}):null;}
  void player?.update(props.live);
},{flush:'post'});
onUnmounted(()=>player?.dispose());
</script>
<template><div class="live-video" :aria-busy="state==='loading'">
  <video ref="video" :aria-label="label" controls autoplay muted playsinline @playing="state='playing';error=''" @error="mediaError" />
  <span class="live-label">实时画面</span>
  <p v-if="state==='loading'" class="live-message" role="status">正在连接设备视频…</p>
  <p v-if="error" class="live-message" role="alert">{{ error }} <button type="button" class="btn small" @click="play">重新播放</button><button v-if="live.hlsUrl && !fallback" type="button" class="btn small" @click="useHls">改用兼容播放</button></p>
  <p v-else-if="state==='playback_blocked'" class="live-message">请点击视频播放按钮开始播放。</p>
</div></template>
<style scoped>.live-video{position:relative;min-height:240px;background:#101621}.live-video video{display:block;width:100%;height:100%;min-height:240px;max-height:60vh;object-fit:contain}.live-label{position:absolute;top:12px;left:12px;background:var(--theme-card);padding:4px 8px;color:var(--theme-text)}.live-message{position:absolute;bottom:48px;left:12px;right:12px;background:var(--theme-card);padding:12px;color:var(--theme-text)}</style>
