import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { parse } from '@vue/compiler-sfc';
import { computed, reactive, ref } from 'vue';
import { createStore } from '../src/mock/data.js';
import { fixtureState } from './fixtures/person-device-data.mjs';

test('长驻总览在快照替换后同步事件增量、核验结果和作业，不依赖重挂载或换厂站', async () => {
  const raw=await readFile(new URL('../src/views/overview/OverviewView.vue',import.meta.url),'utf8');
  const body=parse(raw).descriptor.scriptSetup.content.replace(/^import\s+[\s\S]*?\s+from\s+['"][^'"]+['"];?\s*$/gm,'');
  const db=createStore(null,{demoMode:false}),tick=ref(0),session=reactive({station:'S1',person:'QA-PERSON'});
  db.subscribe(()=>tick.value++);db.replaceRemote(fixtureState('helmet'));
  const scope=()=>({station:session.station});
  const events=()=>db.filter(db.state.events,scope()),works=()=>db.filter(db.state.works,scope());
  const view=new Function('computed','db','revision','events','works','people','videoPeople','session','scope',
    body+'\nreturn {summary,openEvents,jobList};')(computed,db,()=>tick.value,events,works,()=>db.state.people,()=>[],session,scope);
  assert.equal(view.summary.value.unresolved,1);
  assert.deepEqual(view.openEvents.value.map(e=>e.id),['QA-SOS']);
  assert.equal(view.jobList.value.length,1);

  const added=structuredClone(db.state);
  added.events.unshift({...added.events[0],id:'QA-NEW-REPORT',title:'隔离新增设备事件'});
  added.works.push({...added.works[0],id:'QA-WORK-NEW',name:'隔离新作业',members:[]});
  db.replaceRemote(added);
  assert.equal(view.summary.value.unresolved,2);
  assert.deepEqual(view.openEvents.value.map(e=>e.id),['QA-NEW-REPORT','QA-SOS']);
  assert.equal(view.jobList.value.length,2);

  const verified=structuredClone(db.state);
  verified.events.find(e=>e.id==='QA-SOS').status='已核验';
  verified.works.find(w=>w.id==='QA-WORK').name='隔离作业更新后的名称';
  db.replaceRemote(verified);
  assert.equal(view.summary.value.unresolved,1);
  assert.deepEqual(view.openEvents.value.map(e=>e.id),['QA-NEW-REPORT']);
  assert.equal(view.jobList.value.find(w=>w.id==='QA-WORK').name,'隔离作业更新后的名称');

  session.station='NO-FIXTURE-SITE';
  assert.deepEqual(view.openEvents.value,[]);
  assert.deepEqual(view.jobList.value,[]);
});
