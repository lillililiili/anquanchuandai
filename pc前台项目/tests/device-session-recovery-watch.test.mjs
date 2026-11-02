import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { parse, compileScript } from '@vue/compiler-sfc';
import * as Vue from 'vue';

async function fixture({ operatorId='operator-one', status='online' } = {}) {
  const tick=Vue.ref(0), connection=Vue.ref({ status }), db={ state:{operator:{id:operatorId}} };
  const requests=[], transitions=[], listeners=new Set(), unmount=[];
  let state={phase:'idle',recovering:false}, resolve;
  const publish=values=>{state={...state,...values};transitions.push(state.recovering);listeners.forEach(listener=>listener({...state}));};
  const call={
    getState:()=>({...state}),
    subscribe(listener){listeners.add(listener);listener({...state});return()=>listeners.delete(listener);},
    recover(input){requests.push(input);publish({recovering:true});return new Promise(done=>{resolve=()=>{publish({recovering:false});done(true);};});},
    end(){assert.fail('snapshot refresh must not end a call');},
  };
  const modules={
    vue:{...Vue,onUnmounted:fn=>unmount.push(fn)},
    '@/mock/runtime':{db,tick,connection},
    '@/stores/session':{session:Vue.reactive({station:'station-one'})},
    '@/lib/helmet-device-call':{helmetDeviceCall:call,deviceCallStatus:()=>'',deviceCallUnavailable:()=>''},
    '@/lib/live-session':{liveViewing:{dispose(){assert.fail('voice-only watcher must not touch live viewing');}}},
    '@/lib/person-equipment':{personFeature(){assert.fail('idle watcher must not resolve device features');}},
    '@/lib/actions':{runGuarded:fn=>fn(),stopRecording(){assert.fail('must not stop recording');},refreshRecording(){assert.fail('must not query recording');}},
    '@/lib/helmet-media':{COMMAND_STATUSES:{}},'@/stores/notify':{toast(){}},
    '@/components/ui/AppButton.vue':{default:{}},
  };
  const raw=await readFile(new URL('../src/components/domain/DeviceSessionBar.vue',import.meta.url),'utf8');
  const {descriptor}=parse(raw);
  const code=compileScript(descriptor,{id:'device-session-recovery-watch'}).content;
  const compiled=code.replace(/^import\s+([\s\S]*?)\s+from\s+(['"])([^'"]+)\2;?\s*$/gm,(_,names,_quote,from)=>{
    assert.ok(modules[from],`explicit offline dependency: ${from}`);
    const binding=names.trim().startsWith('{')?names.replace(/\bas\b/g,':'):`{default:${names}}`;
    return `const ${binding}=modules[${JSON.stringify(from)}];\n`;
  }).replace('export default','return');
  const component=new Function('modules',compiled)(modules), scope=Vue.effectScope();
  const instance=scope.run(()=>component.setup({voiceOnly:true},{expose(){}}));
  return {db,tick,connection,requests,transitions,instance,
    async finish(){resolve?.();await Vue.nextTick();},
    dispose(){scope.stop();unmount.forEach(fn=>fn());},
  };
}

test('snapshot ticks and equivalent connection objects never repeat automatic call recovery or checking transitions',async()=>{
  const f=await fixture();
  try {
    assert.deepEqual(f.requests,[{operatorId:'operator-one'}]);await f.finish();
    for(let index=0;index<5;index++){
      f.db.state={operator:{id:'operator-one'},snapshotVersion:index};f.tick.value++;
      f.connection.value={status:'online',message:''};await Vue.nextTick();
    }
    assert.equal(f.requests.length,1);
    assert.deepEqual(f.transitions,[true,false]);assert.equal(f.instance.state.value.recovering,false);
    f.db.state.operator={id:'operator-two'};f.tick.value++;await Vue.nextTick();
    assert.deepEqual(f.requests,[{operatorId:'operator-one'},{operatorId:'operator-two'}]);await f.finish();
    f.connection.value={status:'offline'};await Vue.nextTick();assert.equal(f.requests.length,2);
    f.tick.value++;f.connection.value={status:'offline'};await Vue.nextTick();assert.equal(f.requests.length,2);
    f.connection.value={status:'online'};await Vue.nextTick();
    assert.deepEqual(f.requests.at(-1),{operatorId:'operator-two'});assert.equal(f.requests.length,3);await f.finish();
  } finally {f.dispose();}
});

test('automatic recovery waits for both an actor and an online connection, then runs once when they become ready',async()=>{
  const f=await fixture({operatorId:null,status:'connecting'});
  try {
    assert.equal(f.requests.length,0);
    f.connection.value={status:'online'};await Vue.nextTick();assert.equal(f.requests.length,0);
    f.db.state.operator={id:'signed-in-operator'};f.tick.value++;await Vue.nextTick();assert.deepEqual(f.requests,[{operatorId:'signed-in-operator'}]);
    await f.finish();f.db.state={operator:{id:'signed-in-operator'}};f.tick.value++;await Vue.nextTick();
    assert.equal(f.requests.length,1);
  } finally {f.dispose();}
});
