import * as workBusiness from '../src/lib/work-business.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { parse, compileScript } from '@vue/compiler-sfc';
import * as Vue from 'vue';
import { mergeDeviceMedia } from '../src/lib/device-media-state.js';
import * as dateTime from '../src/lib/date-time.js';

const photo={id:'asset-photo',deviceId:'helmet-1',kind:'photo',status:'ready',source:'DIRECT_HELMET',createdAt:'2026-11-02T06:10:00Z'};
test('device uploads merge independently of a platform request, keeping other devices and rejecting mismatched payloads',()=>{
  const existing=[{id:'other',deviceId:'helmet-2',kind:'photo'},{...photo,id:'stale'}];
  const result=mergeDeviceMedia(existing,'helmet-1',[photo,{...photo,id:'wrong',deviceId:'helmet-3'}],'S1');
  assert.deepEqual(result.map(item=>item.id),['other','asset-photo']);
  assert.equal(result[1].requestId,undefined);assert.equal(result[1].station,'S1');assert.equal(result[1].snapshot.personName,'未关联人员');
  assert.equal(result[1].mediaOrigin,undefined);assert.equal(existing.length,2);
  assert.deepEqual(mergeDeviceMedia(result,'helmet-1',[],'S1').map(item=>item.id),['other']);
});

async function recordings() {
  const raw=await readFile(new URL('../src/views/materials/DeviceRecordings.vue',import.meta.url),'utf8');
  const {descriptor}=parse(raw),code=compileScript(descriptor,{id:'device-media-updates'}).content;
  const requests=[],events=[],watchers=[],tick=Vue.ref(0);
  const device={id:'helmet-1',type:'H',source:'DIRECT_HELMET',active:true},feature={deviceId:device.id,assignmentId:'a',assignmentVersion:1,supported:true,available:false};
  const db={state:{operator:{id:'operator'}},currentDevices:()=>[device],device:()=>device,person:()=>({name:'测试人员'})};
  const api={read(){return new Promise((resolve,reject)=>requests.push({resolve,reject}));},command(){assert.fail('passive observation must not issue a device command');}};
  const modules={
    '@/lib/work-business': workBusiness,vue:{...Vue,onUnmounted(){},watch(selector,callback,options){watchers.push(callback);if(options?.immediate)callback();}},'@/mock/runtime':{db,tick,connection:Vue.ref({status:'online'})},'@/lib/auth':{authFetch(){assert.fail('network unavailable in isolated test');}},'@/lib/location':{beijingDate:()=> '2026-11-02'},'@/lib/date-time':dateTime,'@/lib/helmet-media':{COMMAND_LABELS:{},COMMAND_STATUSES:{},createHelmetMediaApi:()=>api},'@/lib/person-equipment':{personFeature:()=>feature,operationContext:()=>({})},'@/lib/device-telemetry':{supportsDeviceAction:()=>false}};
  const compiled=code.replace(/^import\s+([\s\S]*?)\s+from\s+(['"])([^'"]+)\2;?\s*$/gm,(_,names,_quote,from)=>{
    if(from.endsWith('.vue'))modules[from]={default:{}};
    assert.ok(modules[from],from);
    return `const ${names.trim().startsWith('{')?names.replace(/\bas\b/g,':'):`{default:${names}}`}=modules[${JSON.stringify(from)}];\n`;
  }).replace('export default','return');
  const component=new Function('modules','setInterval','clearInterval',compiled)(modules,()=>1,()=>{});
  const instance=component.setup({personId:'P1'},{expose(){},emit:(name,value)=>events.push({name,value})});
  return {instance,requests,events,watchers,feature,tick};
}

test('passive media polling accepts unlinked photos without declaring old timed-out requests successful',async()=>{
  const f=await recordings();
  f.requests.shift().resolve({items:[photo],commands:[{id:'old-command',action:'take_photo',status:'timeout'},{id:'upload',action:'upload_recording',status:'sent'}],recordings:[]});
  await Promise.resolve();await Promise.resolve();
  assert.equal(f.events[0].name,'media');assert.equal(f.events[0].value.items[0].id,photo.id);
  assert.equal(f.instance.commands.value[0].status,'timeout');assert.equal(f.instance.linkedFiles(f.instance.commands.value[0]),0);
  const pending=f.instance.read();f.requests.shift().resolve({items:[{...photo,requestId:'old-command'}],commands:[{id:'old-command',action:'take_photo',status:'completed'}],recordings:[]});await pending;
  assert.equal(f.instance.linkedFiles(f.instance.commands.value[0]),1);
});

test('late media responses after assignment switch are ignored; access revocation clears cached assets',async()=>{
  const f=await recordings(),old=f.requests.shift();
  f.feature.assignmentVersion++;f.tick.value++;f.watchers[0]();
  old.resolve({items:[photo],commands:[],recordings:[]});await Promise.resolve();await Promise.resolve();
  assert.equal(f.events.length,0);
  f.requests.shift().resolve({items:[photo],commands:[],recordings:[]});await Promise.resolve();await Promise.resolve();assert.equal(f.events.length,1);
  const failed=f.instance.read();f.requests.shift().reject(Object.assign(Error('无权限'),{status:403}));await failed;
  assert.deepEqual(f.events.at(-1).value,{deviceId:'helmet-1',items:[],accessDenied:true});assert.deepEqual(f.instance.data.value.items,[]);
});

test('automatic sync progress never creates files, transient media outages preserve existing assets and permission denial clears them',async()=>{
  const f=await recordings();
  f.requests.shift().resolve({items:[photo],itemsAvailable:true,commands:[],recordings:[]});
  await Promise.resolve();await Promise.resolve();
  const task={id:'sync-1',deviceId:'helmet-1',kind:'video',status:'uploading',updatedAt:'2026-11-03T09:00:00Z',fileCount:2,receivedCount:0,message:'设备正在上传'};
  const unavailable=f.instance.read();
  f.requests.shift().resolve({items:[],itemsAvailable:false,commands:[],recordings:[],autoSyncTasks:[task,{...task,id:'another-device',deviceId:'helmet-2'}]});await unavailable;
  assert.deepEqual(f.instance.data.value.items,[photo]);
  assert.equal(f.events.length,1,'unavailable file lists cannot clear or replace the parent preview');
  assert.deepEqual(f.instance.autoSyncTasks.value.map(value=>value.id),['sync-1']);
  assert.equal(f.instance.autoSyncStatus(task),'上传中');
  assert.match(f.instance.error.value,/自动重试/);
  const completed=f.instance.read();
  f.requests.shift().resolve({items:[photo],itemsAvailable:true,commands:[],recordings:[],autoSyncTasks:[{...task,status:'completed',receivedCount:2,assetIds:['video-1','video-2']}]});await completed;
  assert.equal(f.instance.autoSyncStatus(f.instance.autoSyncTasks.value[0]),'已上传');
  assert.deepEqual(f.events.at(-1).value.items,[photo],'task asset IDs must not become playable media cards');
  const failure=f.instance.read();
  f.requests.shift().resolve({items:[photo],itemsAvailable:true,commands:[],recordings:[],autoSyncTasks:[{...task,status:'failed',message:'设备拒绝上传'}]});await failure;
  assert.equal(f.instance.autoSyncStatus(f.instance.autoSyncTasks.value[0]),'上传失败');
  assert.equal(f.instance.autoSyncTasks.value[0].message,'设备拒绝上传');
  const denied=f.instance.read();f.requests.shift().reject(Object.assign(Error('无权限'),{status:403}));await denied;
  assert.deepEqual(f.events.at(-1).value,{deviceId:'helmet-1',items:[],accessDenied:true});
  assert.deepEqual(f.instance.data.value.items,[]);
  assert.deepEqual(f.instance.autoSyncTasks.value,[]);
});

async function library() {
  const raw=await readFile(new URL('../src/views/materials/MaterialsView.vue',import.meta.url),'utf8');
  const {descriptor}=parse(raw),code=compileScript(descriptor,{id:'materials-updates'}).content;
  const requests=[],watchers=[],componentStubs=new Map();
  const db={state:{devices:[{id:'helmet-1',type:'H',source:'DIRECT_HELMET',station:'S1'}],operator:{id:'operator'},media:[photo]},currentDevices:()=>[]};
  const session=Vue.reactive({station:'S1',filters:{},mediaTab:'all'});
  const modalView=Vue.shallowRef(null),modalProps=Vue.shallowRef({});let closes=0;
  const modal={modalView,modalProps,closeModal(){closes++;modalView.value=null;modalProps.value={};},openModal(options){modalView.value=options.view;modalProps.value=options.props;}};
  const modules={
    '@/lib/work-business': workBusiness,vue:{...Vue,onUnmounted(){},watch(selector,callback,options){watchers.push(callback);if(options?.immediate)callback();}},'@/mock/runtime':{db,guardianReady:Promise.resolve()},
    '@/lib/auth':{authFetch:()=>new Promise(resolve=>requests.push(resolve))},'@/lib/media-presentation':{normalizeMedia:identity=>identity,mediaKindLabel:()=>'',mediaSourceLabel:()=>'',mediaTime:()=>({}),mediaPerson:()=>({})},'@/lib/device-telemetry':{isRealDevice:()=>true},
    '@/stores/session':{session,filtersOf:()=>session.filters.materials||{}},'@/stores/modal':modal,'@/stores/notify':{toast(){}},'@/lib/queries':{revision(){},materials:()=>db.state.media,people:()=>[],works:()=>[]},'./media':{downloadMedia(){},durationText(){}},'@/lib/person-equipment':{personFeature:()=>({})},'@/lib/device-media-state':{mergeDeviceMedia}};
  const compiled=code.replace(/^import\s+([\s\S]*?)\s+from\s+(['"])([^'"]+)\2;?\s*$/gm,(_,names,_quote,from)=>{
    if(from.endsWith('.vue')) {if(!componentStubs.has(from))componentStubs.set(from,{});modules[from]={default:componentStubs.get(from)};}
    assert.ok(modules[from],from);
    return `const ${names.trim().startsWith('{')?names.replace(/\bas\b/g,':'):`{default:${names}}`}=modules[${JSON.stringify(from)}];\n`;
  }).replace('export default','return');
  const component=new Function('modules','setInterval','clearInterval',compiled)(modules,()=>1,()=>{});
  const instance=component.setup({}, {expose(){}});
  const response=(items,status=200)=>({ok:status===200,status,json:async()=>({items,message:status===200?'':'无权限'})});
  const flush=async()=>{for(let index=0;index<10;index++)await Promise.resolve();};
  await flush();requests.shift()(response([photo]));await flush();
  return {instance,requests,watchers,session,modal,db,response,flush,closeCount:()=>closes};
}

test('an older library refresh cannot overwrite a newer passive upload or clear an open preview',async()=>{
  const f=await library();
  f.instance.openPreview(photo.id);const activePreview=f.modal.modalView.value;
  const pending=f.instance.refreshDeviceMedia();await f.flush();
  assert.equal(f.instance.deviceMedia.value[0].id,photo.id,'existing cards remain while refreshing');
  f.instance.receiveDeviceMedia({deviceId:'helmet-1',items:[photo,{...photo,id:'new-upload'}]});
  f.requests.shift()(f.response([photo]));await pending;
  assert.deepEqual(f.instance.deviceMedia.value.map(item=>item.id),[photo.id,'new-upload']);
  assert.equal(f.modal.modalView.value,activePreview,'ordinary refresh preserves current playback');assert.equal(f.closeCount(),0);
});

test('permission rejection closes the matching preview and removes both API and snapshot copies',async()=>{
  const f=await library();f.instance.openPreview(photo.id);
  f.instance.receiveDeviceMedia({deviceId:'helmet-1',items:[],accessDenied:true});
  assert.equal(f.closeCount(),1);assert.equal(f.instance.mediaList.value.length,0);assert.deepEqual(f.instance.deviceMedia.value,[]);
  f.instance.receiveDeviceMedia({deviceId:'helmet-other',items:[photo]});assert.equal(f.instance.deviceMedia.value.length,0);
});

test('changing site clears old files and rejects late responses from the previous site',async()=>{
  const f=await library();f.instance.openPreview(photo.id);
  const pending=f.instance.refreshDeviceMedia();await f.flush();const old=f.requests.shift();
  f.session.station='S2';f.watchers[0]();await f.flush();
  old(f.response([photo]));await pending;
  assert.equal(f.instance.deviceMedia.value.length,0);assert.equal(f.closeCount(),1);
});

test('a successful filtered response also revokes the removed file preview, while same-account permission changes discard old responses',async()=>{
  const f=await library();f.instance.openPreview(photo.id);
  f.instance.receiveDeviceMedia({deviceId:'helmet-1',items:[]});assert.equal(f.closeCount(),1);
  f.instance.receiveDeviceMedia({deviceId:'helmet-1',items:[photo]});f.instance.openPreview(photo.id);
  const pending=f.instance.refreshDeviceMedia();await f.flush();const old=f.requests.shift();
  f.db.state.operator.permissionsBySite={'site-1':[]};f.watchers[0]();await f.flush();
  old(f.response([photo]));await pending;assert.equal(f.instance.deviceMedia.value.length,0);assert.equal(f.closeCount(),2);
  f.requests.shift()(f.response([],403));await f.flush();assert.equal(f.instance.mediaList.value.length,0);
});

test('a transferred device loses its local cache but keeps historical media authorized by the latest server snapshot',async()=>{
  const f=await library();f.instance.receiveDeviceMedia({deviceId:'helmet-1',items:[photo,{...photo,id:'cached-only'}]});
  f.instance.openPreview(photo.id);f.db.state.devices=[];
  f.instance.receiveDeviceMedia({deviceId:'helmet-1',items:[photo]});
  assert.equal(f.instance.deviceMedia.value.length,0);assert.equal(f.closeCount(),1);
  assert.deepEqual(f.instance.mediaList.value.map(item=>item.id),[photo.id],'the server-authorized historical asset survives; the old cached-only asset does not');
  f.db.state.media=[];f.instance.receiveDeviceMedia({deviceId:'helmet-1',items:[]});
  assert.equal(f.instance.mediaList.value.length,0,'history removed by the latest authorized snapshot cannot return from the local cache');
});

test('an event filter keeps linked evidence scoped until explicitly cleared without losing other filters',async()=>{
  const f=await library();
  f.instance.receiveDeviceMedia({deviceId:'helmet-1',items:[
    {...photo,id:'event-photo',personId:'P1',eventId:'E1'},
    {...photo,id:'button-photo',personId:'P1'},
    {...photo,id:'other-person',personId:'P2'},
  ]});
  f.session.filters.materials={eventId:'E1',personId:'P1',deviceId:'helmet-1'};
  f.instance.readDraft();
  assert.deepEqual(f.instance.mediaList.value.map(item=>item.id),['event-photo']);
  f.session.filters.materials.eventId='event-without-files';
  assert.equal(f.instance.mediaList.value.length,0);
  assert.match(f.instance.emptyText.value,/事件.*清除事件筛选/);
  f.instance.clearEventFilter();
  assert.deepEqual(f.session.filters.materials,{personId:'P1',deviceId:'helmet-1'});
  assert.equal(f.instance.draft.eventId,'');
  assert.deepEqual(f.instance.mediaList.value.map(item=>item.id),['event-photo','button-photo']);
  f.instance.resetFilters();
  assert.deepEqual(f.session.filters.materials,{});
  assert.equal(f.instance.draft.personId,'');
  assert.deepEqual(f.instance.mediaList.value.map(item=>item.id),['event-photo','button-photo','other-person']);
});

test('person filtering includes frozen photo receipt association without changing historical capture identity',async()=>{
  const f=await library();
  f.instance.receiveDeviceMedia({deviceId:'helmet-1',items:[
    {...photo,id:'captured',personId:'P1'},
    {...photo,id:'received',receivedPersonId:'P1',receivedPersonName:'接收时姓名',timeBasis:'RECEIVED_AT'},
    {...photo,id:'other-recipient',receivedPersonId:'P2'},
  ]});
  f.session.filters.materials={personId:'P1'};
  assert.deepEqual(f.instance.mediaList.value.map(item=>item.id),['captured','received']);
  assert.equal(f.instance.mediaList.value[1].personId,undefined);
  f.session.filters.materials={personId:'P2'};
  assert.deepEqual(f.instance.mediaList.value.map(item=>item.id),['other-recipient']);
});
