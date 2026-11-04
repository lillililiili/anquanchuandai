import * as workBusiness from '../src/lib/work-business.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { parse, compileScript } from '@vue/compiler-sfc';
import * as Vue from 'vue';
import * as wall from '../src/views/video/video-wall.js';

const channels=count=>Array.from({length:count},(_,index)=>({id:`P${index+1}`,name:`隔离通道${index+1}`,online:true,workId:index<10?'work-one':'work-two'}));

test('grid capacity is eight or nine real channels with no duplicate padding and clamped final pages',()=>{
  const cameras=channels(20);
  for(const [layout,capacity] of [['2×4',8],['3×3',9]]) {
    const pages=Array.from({length:3},(_,page)=>wall.videoGridPage(cameras,layout,page));
    assert.deepEqual(pages.map(page=>page.items.length),[capacity,capacity,20-2*capacity]);
    assert.deepEqual(pages.flatMap(page=>page.items).map(person=>person.id),cameras.map(person=>person.id));
    assert.equal(wall.videoGridPage(cameras,layout,99).page,2);
    assert.equal(wall.videoGridPage(cameras,layout,-2).page,0);
    assert.equal(wall.videoGridPage(channels(1),layout).items.length,1);
    assert.deepEqual(wall.videoGridPage([],layout).items,[]);
  }
});

async function fixture(count=20) {
  const tick=Vue.ref(0), session=Vue.reactive({layout:'2×4',person:'P1',station:'S1',rotation:false,filters:{video:{}}});
  const db={state:{businessConfig:{workBusinessEnabled:true}},people:channels(count),currentWork(id){const person=this.people.find(person=>person.id===id);return person?{id:person.workId}:null;}};
  const timers=new Map(), cleanups=[];let timerId=0;
  const modules={
    '@/lib/work-business': workBusiness,
    vue:{...Vue,onUnmounted:fn=>cleanups.push(fn)},'@/mock/runtime':{db},'@/stores/notify':{toast(){}},
    '@/stores/session':{session,filtersOf:key=>session.filters[key]},
    '@/lib/queries':{revision(){tick.value;},people:()=>db.people,works:()=>[{id:'work-one',name:'隔离作业一'},{id:'work-two',name:'隔离作业二'}],helmetOf:()=>({id:'offline-test-device'}),personName:()=>''},
    '@/lib/device-telemetry':{isRealDevice:()=>true},'@/lib/person-duty':{personDutyPresentation:()=>({})},
    '@/lib/person-equipment':{videoPeople:(_db,list)=>list,personFeature:(_db,id)=>({available:db.people.find(person=>person.id===id)?.online===true})},
    './video-wall':wall,
  };
  const raw=await readFile(new URL('../src/views/video/VideoView.vue',import.meta.url),'utf8');const {descriptor}=parse(raw);
  const code=compileScript(descriptor,{id:'video-wall-behavior'}).content;
  const compiled=code.replace(/^import\s+([\s\S]*?)\s+from\s+(['"])([^'"]+)\2;?\s*$/gm,(_,names,_quote,from)=>{
    if(from.endsWith('.vue'))modules[from]={default:{}};
    assert.ok(modules[from],`explicit isolated dependency: ${from}`);
    const binding=names.trim().startsWith('{')?names.replace(/\bas\b/g,':'):`{default:${names}}`;
    return `const ${binding}=modules[${JSON.stringify(from)}];\n`;
  }).replace('export default','return');
  const component=new Function('modules','setInterval','clearInterval',compiled)(modules,(fn,delay)=>{const id=++timerId;timers.set(id,{fn,delay});return id;},id=>timers.delete(id));
  const scope=Vue.effectScope(),instance=scope.run(()=>component.setup({}, {expose(){}}));await Vue.nextTick();
  return{db,tick,session,timers,instance,async rotate(){const timer=[...timers.values()][0];assert.ok(timer,'rotation has one page-owned timer');assert.equal(timer.delay,30000);timer.fn();await Vue.nextTick();},dispose(){scope.stop();cleanups.forEach(fn=>fn());}};
}

test('grid rotation advances complete screens, wraps, pauses on manual paging and stops after the page unmounts',async()=>{
  const f=await fixture();
  try {
    assert.deepEqual(f.instance.grid.value.items.map(person=>person.id),channels(8).map(person=>person.id));
    f.session.rotation=true;await Vue.nextTick();await f.rotate();
    assert.equal(f.instance.grid.value.page,1);assert.equal(f.instance.grid.value.items[0].id,'P9');assert.equal(f.session.person,'P9');
    await f.rotate();assert.equal(f.instance.grid.value.items.length,4);await f.rotate();assert.equal(f.instance.grid.value.page,0);
    f.instance.changePage(1);await Vue.nextTick();assert.equal(f.session.rotation,false);assert.equal(f.timers.size,0);
    f.session.rotation=true;await Vue.nextTick();assert.equal(f.timers.size,1);
  } finally {f.dispose();}
  assert.equal(f.timers.size,0);
});

test('layout and filter changes reset page capacity; a single screen never claims active rotation',async()=>{
  const f=await fixture();
  try {
    f.instance.changePage(2);await Vue.nextTick();assert.equal(f.instance.grid.value.page,2);
    f.session.layout='3×3';await Vue.nextTick();assert.equal(f.instance.grid.value.page,0);assert.equal(f.instance.grid.value.items.length,9);
    f.session.filters.video={workId:'work-two'};await Vue.nextTick();assert.equal(f.instance.cameras.value.length,10);assert.equal(f.instance.grid.value.pages,2);
    f.instance.changePage(1);await Vue.nextTick();assert.equal(f.instance.grid.value.items.length,1);
    f.db.people=f.db.people.filter(person=>person.id==='P20');f.tick.value++;await Vue.nextTick();
    assert.equal(f.instance.grid.value.page,0);assert.equal(f.instance.grid.value.items.length,1);assert.equal(f.instance.canRotate.value,false);
    f.session.rotation=true;await Vue.nextTick();assert.equal(f.session.rotation,false);assert.equal(f.timers.size,0);
  } finally {f.dispose();}
});

test('main-focus layout rotates only available actual channels and preserves offline thumbnails',async()=>{
  const f=await fixture(3);
  try {
    f.session.layout='1+7';f.db.people[1].online=false;f.tick.value++;await Vue.nextTick();
    assert.equal(f.instance.cameras.value.length,3);assert.deepEqual(f.instance.rotatable.value.map(person=>person.id),['P1','P3']);
    f.session.rotation=true;await Vue.nextTick();await f.rotate();assert.equal(f.instance.focus.value.id,'P3');
    await f.rotate();assert.equal(f.instance.focus.value.id,'P1');
  } finally {f.dispose();}
});
