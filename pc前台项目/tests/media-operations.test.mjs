import test from 'node:test';
import assert from 'node:assert/strict';
import { createMediaOperations } from '../src/lib/media-operations.js';
const context={personId:'P1',deviceId:'H1',assignmentId:'A1',assignmentVersion:1};
function fixture(command,read=async()=>({commands:[]})) {
  let i=0;const state={recording:null}, calls=[];
  const api={command(...args){calls.push(args);return command(...args);},read};
  return {state,calls,manager:createMediaOperations({api,state,makeId:()=>`key-${++i}`})};
}
test('double start shares the pending recorder and does not send a second command',async()=>{
  let finish;const f=fixture(()=>new Promise(resolve=>{finish=resolve;}));
  const first=f.manager.start(context),second=f.manager.start(context);
  assert.equal(f.calls.length,1);assert.equal(f.state.recording.status,'requesting');
  finish({id:'C1',status:'waiting_media'});await Promise.all([first,second]);assert.equal(f.state.recording.commandId,'C1');
});
test('uncertain start is recovered from history and stops with original assignment and command',async()=>{
  const f=fixture(async(_id,action)=>{if(action==='start_recording')throw Error('network');return {id:'S1',status:'completed'};},async()=>({commands:[{id:'C1',requestId:'key-1',status:'recording'}]}));
  await assert.rejects(f.manager.start(context));await assert.rejects(f.manager.start({...context,assignmentId:'A2'}));
  await f.manager.stop();const stop=f.calls.find(call=>call[1]==='stop_recording');
  assert.equal(stop[5].assignmentId,'A1');assert.equal(stop[5].sourceCommandId,'C1');assert.equal(f.state.recording,null);
});
test('receipts update actual recording then retain finalizing until the file completes',async()=>{
  let rows=[{id:'C1',status:'recording'}];
  const f=fixture(async(_id,action)=>action==='start_recording'?{id:'C1',status:'waiting_media'}:{id:'S1',status:'finalizing'},async()=>({commands:rows}));
  await f.manager.start(context);await f.manager.refresh();assert.equal(f.state.recording.status,'recording');
  await f.manager.stop();assert.equal(f.state.recording.status,'finalizing');
  rows.push({id:'S1',status:'completed',message:'file ready'});await f.manager.refresh();assert.equal(f.state.recording,null);
});
test('a failed stop remains recoverable and explicit retries keep the same request key',async()=>{
  let count=0;const f=fixture(async(_id,action)=>action==='start_recording'?{id:'C1',status:'recording'}:++count===1?{id:'S1',status:'unknown'}:{id:'S1',status:'completed'},async()=>({commands:[{id:'C1',status:'recording'},{id:'S1',status:'unknown'}]}));
  await f.manager.start(context);await assert.rejects(f.manager.stop());await f.manager.refresh();assert.ok(f.state.recording);
  await f.manager.stop();const stops=f.calls.filter(call=>call[1]==='stop_recording');assert.equal(stops[0][3],stops[1][3]);
});
test('photo double-click and uncertain retry preserve one idempotency key',async()=>{
  let count=0,finish;const f=fixture(()=>++count===1?new Promise((_,reject)=>{finish=reject;}):Promise.resolve({status:'completed'}));
  const a=f.manager.photo(context),b=f.manager.photo(context);assert.equal(f.calls.length,1);finish(Error('network'));
  await Promise.allSettled([a,b]);await f.manager.photo(context);assert.equal(f.calls[0][3],f.calls[1][3]);
});
test('a completed source clears an earlier failed stop without reporting the failure as completion',async()=>{
  const f=fixture(async(_id,action)=>action==='start_recording'?{id:'C1',status:'recording'}:{id:'S1',status:'timeout'},async()=>({commands:[{id:'C1',status:'completed',message:'录像文件已保存'},{id:'S1',status:'timeout'}]}));
  await f.manager.start(context);await assert.rejects(f.manager.stop());const result=await f.manager.refresh();
  assert.equal(result.status,'completed');assert.equal(result.message,'录像文件已保存');assert.equal(f.state.recording,null);
});
