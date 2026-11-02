import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { parse, compileScript } from '@vue/compiler-sfc';
import * as Vue from 'vue';
import * as SSR from 'vue/server-renderer';
import * as presentation from '../src/lib/media-presentation.js';
import { mediaUrl, mediaDownloadUrl } from '../src/lib/helmet-media.js';

// Structure of the real 2026-11-02 recording response, excluding its signed URL.
const asset = { id:'3c51dad0-287d-4242-aaf8-707692e453cd', requestId:'HC-d0e984fc-9bc1-4114-92e2-1fc76b6100b6',
  deviceId:'866652021714127', personId:'people-19007199254740993-20', siteId:'site-1', status:'ready', kind:'video',
  source:'DIRECT_HELMET', createdAt:'2026-11-02T01:37:50.612Z', name:'3c51dad0-287d-4242-aaf8-707692e453cd', size:7123674 };

test('actual media without duration or historical name preserves unknowns and formats the real creation time', () => {
  const value = presentation.normalizeMedia(asset);
  assert.equal(presentation.durationText(value.duration), '时长未提供');
  assert.deepEqual(presentation.mediaTime(value), { label:'资料生成时间', value:'2026-11-02 09:37:50' });
  assert.equal(value.date, '2026-11-02');
  assert.equal(value.title, asset.name);
  assert.equal(value.snapshot.personName, asset.personId + '（历史姓名未提供）');
  assert.equal(presentation.mediaSourceLabel(value), '安全帽直连接入');
  assert.equal(presentation.mediaKindLabel(value), '录像（录制来源未确认）');
  assert.equal(presentation.mediaKindLabel({ ...value, url:'https://example.invalid/record.mp4' }), '录像（录制来源未确认）');
});

test('recording origin comes from explicit origin or correlated command, never from presence or absence of URL', () => {
  assert.equal(presentation.mediaKindLabel({ ...asset, mediaOrigin:'PLATFORM_RECORDING' }), '平台录制');
  assert.equal(presentation.mediaKindLabel({ ...asset, mediaOrigin:'DEVICE_RECORDING' }), '设备内录像');
  assert.equal(presentation.mediaKindLabel({ ...asset, commandAction:'start_recording' }), '平台录制');
  assert.equal(presentation.mediaKindLabel({ ...asset, mediaOrigin:'UNKNOWN', commandAction:'start_recording' }), '录像（录制来源未确认）');
  assert.equal(presentation.mediaKindLabel({ ...asset, kind:'photo' }), '照片');
  assert.equal(presentation.normalizeMedia({ ...asset, snapshot:{}, personName:'记录时姓名' }).snapshot.personName, '记录时姓名');
  assert.equal(presentation.normalizeMedia({ ...asset, snapshot:{personName:'冻结姓名'}, personName:'其他字段姓名' }).snapshot.personName, '冻结姓名');
});

test('unknown, zero, fractional and long durations are not confused', () => {
  for (const value of [undefined,null,'',' ',NaN,Infinity,-1,true,'bad']) assert.equal(presentation.durationText(value), '时长未提供');
  assert.equal(presentation.durationText(0), '00:00');
  assert.equal(presentation.durationText(43.6), '00:43');
  assert.equal(presentation.durationText(3601), '60:01');
});

async function previewHtml(demoMode, media) {
  const raw = await readFile(new URL('../src/views/event/EventMediaPreview.vue', import.meta.url),'utf8');
  const { descriptor } = parse(raw);
  const code = compileScript(descriptor, { id:'event-media-preview-test', inlineTemplate:true, templateOptions:{ssr:true} }).content;
  const modules = { vue:Vue, 'vue/server-renderer':SSR, '@/lib/helmet-media':{mediaUrl}, '@/mock/runtime':{db:{demoMode}}, '@/lib/media-presentation':presentation };
  const compiled = code.replace(/^import\s+([\s\S]*?)\s+from\s+(['"])([^'"]+)\2;?\s*$/gm, (_,names,_quote,from) => {
    if (from.endsWith('.vue')) modules[from]={default:Vue.defineComponent({setup:()=>()=>Vue.h('section')})};
    assert.ok(modules[from],from);
    return `const ${names.trim().startsWith('{')?names.replace(/\bas\b/g,':'):`{default:${names}}`}=modules[${JSON.stringify(from)}];\n`;
  }).replace('export default','return');
  return SSR.renderToString(Vue.createSSRApp(new Function('modules',compiled)(modules),{media}));
}

test('production event evidence without a file cannot expose simulated playback; real files keep native video controls', async () => {
  const missing = await previewHtml(false, asset);
  assert.doesNotMatch(missing, /模拟回放|type="range"/);
  const real = await previewHtml(false, { ...asset, mediaOrigin:'PLATFORM_RECORDING', url:'https://example.invalid/record.mp4' });
  assert.match(real, /<video[^>]*controls[^>]*aria-label="平台录制"/);
  assert.match(real, /资料生成时间：2026-11-02 09:37:50/);
  assert.match(await previewHtml(true,{...asset,duration:38}), /图片模拟回放/);
});

test('production download without a file refuses rather than generating a simulated recording', async () => {
  const raw = await readFile(new URL('../src/views/materials/media.js',import.meta.url),'utf8');
  const code=raw.replace(/^import .*;\s*$/gm,'').replace(/^export \{.*;\s*$/gm,'').replace('export async function downloadMedia','async function downloadMedia');
  let downloads=0;
  const downloadMedia=new Function('db','toast','blobGet','download','imageBlob','mediaDownloadUrl',code+'\nreturn downloadMedia;')({demoMode:false},()=>{},async()=>null,()=>{downloads++;},async()=>null,mediaDownloadUrl);
  await assert.rejects(downloadMedia(asset),/暂无可下载的原始文件/);
  assert.equal(downloads,0);
});

test('download preserves the cloud asset and its authorization while preview remains inline', () => {
  const original='https://media.example.invalid/helmet-media/files/cloud-asset?token=fake-token&other=unchanged';
  const result=new URL(mediaDownloadUrl(original));
  assert.equal(result.pathname,'/helmet-media/files/cloud-asset');
  assert.equal(result.searchParams.get('token'),'fake-token');
  assert.equal(result.searchParams.get('other'),'unchanged');
  assert.equal(result.searchParams.get('download'),'1');
  assert.equal(mediaUrl(original),original);
  assert.equal(new URL(mediaDownloadUrl(original+'&download=0&download=0')).searchParams.getAll('download').length,1);
  for(const invalid of ['javascript:alert(1)','https://name:pass@example.invalid/helmet-media/files/id','https://example.invalid/other/id','https://example.invalid/helmet-media/files/a/b','https://example.invalid/helmet-media/files/a%2Fb'])assert.equal(mediaDownloadUrl(invalid),null);
});

test('real download delegates attachment delivery to the server without a blob or preview tab', async () => {
  const raw=await readFile(new URL('../src/views/materials/media.js',import.meta.url),'utf8');
  const code=raw.replace(/^import .*;\s*$/gm,'').replace(/^export \{.*;\s*$/gm,'').replace('export async function downloadMedia','async function downloadMedia');
  const clicks=[],messages=[];
  const document={createElement:()=>({click(){clicks.push({...this});}})};
  const noBlob=()=>{throw Error('must not buffer a real media file');};
  const run=new Function('db','toast','blobGet','download','imageBlob','mediaDownloadUrl','document',code+'\nreturn downloadMedia;')({demoMode:false},message=>messages.push(message),noBlob,noBlob,noBlob,mediaDownloadUrl,document);
  await run({...asset,id:'imported-business-id',url:'https://media.example.invalid/helmet-media/files/cloud-asset?token=fake-token'});
  assert.equal(clicks.length,1);
  assert.equal(new URL(clicks[0].href).searchParams.get('download'),'1');
  assert.equal(clicks[0].target,undefined);
  assert.match(messages[0],/已请求下载/);
  await assert.rejects(run({...asset,url:'https://media.example.invalid/helmet-media/files/cloud-asset?token=fake-token',expiresAt:'2000-01-01T00:00:00Z'}),/授权已过期/);
  assert.equal(clicks.length,1);
});
