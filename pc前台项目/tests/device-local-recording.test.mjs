import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { parse, compileScript } from '@vue/compiler-sfc';
import * as Vue from 'vue';
import * as SSR from 'vue/server-renderer';
import * as observations from '../../shared/device-local-recording.mjs';
import { deviceControlsReference } from '../../shared/device-controls.mjs';
import * as dateTime from '../src/lib/date-time.js';

const report = { source:'DIRECT_HELMET', reportAct:'toggle_localrecord', timeBasis:'RECEIVED_AT', rawType:'0', state:'RECORDING', receivedAt:'2026-11-02T06:20:30.123456789Z', personName:'上报时人员' };
const device = { type:'H', source:'DIRECT_HELMET', online:false, localRecording:report };

test('last local recording observation stays historical when offline and cannot enable platform recording', () => {
  const source=structuredClone(device), before=structuredClone(source);
  const value=observations.deviceLocalRecordingPresentation(source);
  assert.equal(value.label,'开启');assert.equal(value.personLabel,'上报时人员');
  assert.equal(dateTime.formatBeijingDateTime(value.receivedAt),'2026-11-02 14:20:30');
  assert.match(value.note,/不代表当前仍在录制或文件已生成/);
  assert.equal(observations.deviceLocalRecordingPresentation({...source,online:true}).label,'开启');
  assert.equal(observations.deviceLocalRecordingPresentation({...source,localRecording:{...report,rawType:'1',state:'STOPPED'}}).label,'关闭');
  assert.deepEqual(source,before);assert.equal(value.available,undefined);
});

test('missing, unknown codes, mismatched meanings and untrusted observations cannot claim a recording state', () => {
  assert.equal(observations.deviceLocalRecordingPresentation({...device,localRecording:undefined}).label,'暂无上报');
  for (const change of [{rawType:'2'},{rawType:0},{rawType:'1'},{state:'UNKNOWN'},{source:'PLATFORM'},{reportAct:'heartbeat'},{timeBasis:'DEVICE_TIME'}]) {
    assert.equal(observations.deviceLocalRecordingPresentation({...device,localRecording:{...report,...change}}).label,'状态未知');
  }
  for (const receivedAt of ['',undefined,'bad','2026-11-02 14:20:30','2026-02-30T00:00:00Z','2026-11-02T24:00:00Z']) assert.equal(observations.deviceLocalRecordingPresentation({...device,localRecording:{...report,receivedAt}}).receivedAt,null);
  assert.equal(observations.deviceLocalRecordingPresentation({...device,source:'DIRECT_BELT'}).visible,false);
  assert.equal(observations.deviceLocalRecordingPresentation({...device,type:'B'}).visible,false);
  assert.equal(observations.deviceLocalRecordingPresentation({...device,simulated:true}).visible,false);
  assert.equal(observations.deviceLocalRecordingPresentation({...device,demo:true}).visible,false);
  assert.equal(observations.deviceLocalRecordingPresentation({...device,localRecording:{...report,source:'PLATFORM'}}).personLabel,'归属未确认');
});

test('model-labelled button reference is only offered for matching real device types, never as a command', () => {
  assert.equal(deviceControlsReference(device).model,'RD-D1+');
  assert.equal(deviceControlsReference({source:'DIRECT_HELMET',type:'HELMET'}).model,'RD-D1+');
  assert.equal(deviceControlsReference({source:'DIRECT_BELT',type:'BELT'}).model,'RD-1102');
  for(const input of [null,{source:'DIRECT_HELMET',type:'B'},{source:'DIRECT_BELT',type:'H'},{source:'DEMO_WATCH',type:'W'},{source:'PLATFORM',type:'H'},{...device,simulated:true},{...device,demo:true}])assert.equal(deviceControlsReference(input),null);
  assert.ok(deviceControlsReference(device).controls.every(control=>!control.command&&!control.action));
});

test('observation renders a read-only dated value without any control or current-recording claim', async () => {
  const raw=await readFile(new URL('../src/components/domain/DeviceLocalRecording.vue',import.meta.url),'utf8');
  const {descriptor}=parse(raw);
  const code=compileScript(descriptor,{id:'local-recording',inlineTemplate:true,templateOptions:{ssr:true}}).content;
  const modules={vue:Vue,'vue/server-renderer':SSR,'../../../../shared/device-local-recording.mjs':observations,'@/lib/date-time':dateTime};
  const compiled=code.replace(/^import\s+([\s\S]*?)\s+from\s+(['"])([^'"]+)\2;?\s*$/gm,(_,names,_quote,from)=>`const ${names.replace(/\bas\b/g,':')}=modules[${JSON.stringify(from)}];\n`).replace('export default','return');
  const component=new Function('modules',compiled)(modules);
  const html=await SSR.renderToString(Vue.createSSRApp(component,{device}));
  assert.match(html,/设备本地录像 · 最后上报/);assert.match(html,/平台接收时间：2026-11-02 14:20:30/);
  assert.match(html,/上报时人员：上报时人员/);assert.doesNotMatch(html,/<button|<input|正在录制/);
  const missing=await SSR.renderToString(Vue.createSSRApp(component,{device:{...device,localRecording:undefined}}));
  assert.match(missing,/暂无上报/);assert.doesNotMatch(missing,/2026-/);
});
