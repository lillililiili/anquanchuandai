import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { parse } from '@vue/compiler-sfc';
import { ref, watch } from 'vue';

test('changing station clears the previous fence editing mode and undo history before selecting the new station', async () => {
  const source = await readFile(new URL('../src/components/layout/Topbar.vue', import.meta.url), 'utf8');
  const body = source.slice(source.indexOf('function changeStation(value)'), source.indexOf('function openScreen(event)'));
  const session = { station:'S1', person:'P1', fenceDraft:{ station:'S1', points:[[117,36],[117.1,36],[117,36.1]] },
    fenceMode:'draw', fenceUndo:[[[116,35],[116.1,35],[116,35.1]]], filters:{fences:{status:'on'}}, selectedMembers:['P1'] };
  const saved=[], location={hash:'#/fences'}; let closed=0;
  const bindings={session,TEST_SITE_MODE:false,TEST_SITE:{},localStorage:{setItem:(...args)=>saved.push(args)},
    people:()=>session.station==='S2'?[{id:'P2'}]:[{id:'P1'}],closeModal:()=>closed++,route:{name:'fences'},location};
  const changeStation=new Function(...Object.keys(bindings),body+'\nreturn changeStation;')(...Object.values(bindings));
  changeStation('S2');
  assert.equal(session.station,'S2');
  assert.equal(session.person,'P2');
  assert.equal(session.fenceDraft,null);
  assert.deepEqual(session.fenceUndo,[],'undo cannot restore polygon coordinates from the previous station');
  assert.equal(session.fenceMode,'select','a new station must not inherit an active drawing gesture');
  assert.deepEqual(session.selectedMembers,[]);
  assert.deepEqual(session.filters,{});
  assert.equal(closed,1);
  assert.deepEqual(saved,[['rolling-station','S2']]);
});

async function loginFixture({ snapshot=true, status=200 } = {}) {
  const raw=await readFile(new URL('../src/views/login/LoginView.vue',import.meta.url),'utf8');
  const body=parse(raw).descriptor.scriptSetup.content.replace(/^import\s+[\s\S]*?\s+from\s+['"][^'"]+['"];?\s*$/gm,'');
  const saved=[], destinations=[], state={token:'',account:'',clearCount:0};
  const session={station:'old-site',formDrafts:{'old-event':{situation:'old-account-draft'}}};
  const bindings={ref,watch,session,useFieldErrors:()=>({formRef:ref(null),errors:ref({}),validate:()=>true}),
    saveAuth:(token,account)=>{state.token=token;state.account=account;saved.push(token);},
    authHeaders:()=>({'X-Wearable-Token':state.token}),
    clearAuth:()=>{state.token='';state.account='';state.clearCount++;},
    db:{state:{stations:[{id:'new-site'}]}},refreshSnapshot:async()=>snapshot,
    TEST_SITE_MODE:false,TEST_SITE:{},go:destination=>destinations.push(destination),
    fetch:async()=>({ok:status===200,status,json:async()=>status===200?{token:'new-token'}:{message:'账号或密码错误。'}})};
  const view=new Function(...Object.keys(bindings),body+'\nreturn {submit,account,password,error,busy};')(...Object.values(bindings));
  view.account.value='new-account';view.password.value='test-password';
  return {view,session,state,saved,destinations};
}

test('a login whose initial authorized snapshot fails cannot enter protected routes with the previous cached data', async () => {
  const f=await loginFixture({snapshot:false});
  await f.view.submit();
  assert.deepEqual(f.saved,['new-token']);
  assert.equal(f.state.token,'','failed login initialization must revoke its provisional local credential');
  assert.equal(f.state.account,'','the rolling-session route guard must remain closed');
  assert.equal(f.state.clearCount,1);
  assert.ok(f.view.error.value);
  assert.deepEqual(f.destinations,[]);
  assert.equal(f.view.busy.value,false);
});

test('a successful login selects an authorized station and clears previous account form drafts', async () => {
  const f=await loginFixture();
  await f.view.submit();
  assert.equal(f.state.token,'new-token');
  assert.equal(f.state.clearCount,0);
  assert.equal(f.session.station,'new-site');
  assert.deepEqual(f.session.formDrafts,{});
  assert.deepEqual(f.destinations,['overview']);
  assert.equal(f.view.error.value,'');
  assert.equal(f.view.busy.value,false);
});

test('rejected credentials neither save a session nor navigate away from login', async () => {
  const f=await loginFixture({status:401});
  await f.view.submit();
  assert.deepEqual(f.saved,[]);
  assert.deepEqual(f.destinations,[]);
  assert.equal(f.state.clearCount,0);
  assert.equal(f.view.error.value,'账号或密码错误。');
  assert.equal(f.view.busy.value,false);
});
