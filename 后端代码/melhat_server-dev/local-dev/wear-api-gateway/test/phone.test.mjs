import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { createServer } from 'node:http';
import { once } from 'node:events';
import { PhoneCalls, phoneIdentityReader } from '../phone-calls.mjs';
import { createWearGateway } from '../gateway.mjs';

const roster = new Map(['alice', 'bob', 'chen', 'dan'].map(p => [p, p]));
function fixture() {
  let time = 0;
  let issued = 0;
  const accounts = new Map([...roster.keys()].map(id => [id, {
    id, personId: id, name: id, canDial: true, visible: new Map(roster),
  }]));
  const phones = new PhoneCalls({
    now: () => time, relay: () => [{ urls: 'turn:example.invalid', username: String(++issued) }],
    identity: async token => accounts.get(token),
  });
  const clients = new Map([...accounts.keys()].map(p => [p, randomUUID()]));
  const send = (user, action = 'presence', data = {}) => phones.handle(action, user, {
    clientId: clients.get(user), siteId: 's1', ...data,
  });
  return { send, accounts, advance: ms => { time += ms; } };
}
const sdp = 'v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n';

test('multi-phone call rings registered people, offers only after acceptance, hangs up by room', async () => {
  const { send } = fixture();
  await Promise.all(['bob','chen','dan'].map(id => send(id)));
  const request = { requestId: randomUUID(), personIds: ['bob','chen'] };
  const { call } = await send('alice','start',request);
  assert.equal((await send('alice','start',request)).call.id, call.id);
  const peer = async (name, action = 'presence', body = {}) => (await send(name, action, {callId: call.id, ...body})).call;
  const bob = await peer('bob');
  assert.deepEqual(bob.iceByPeer, {});
  assert.equal(bob.members.find(m => m.id === bob.self).state, 'ringing');
  await assert.rejects(peer('alice','signal',{ to: bob.self, type:'offer', sdp }), {status:409});
  await assert.rejects(peer('dan','accept'), {status:404});
  await peer('bob', 'accept');
  const chen = await peer('chen','accept');
  const alice = await peer('alice');
  assert.equal(Object.keys(alice.iceByPeer).length, 2);
  assert.notEqual(alice.iceByPeer[bob.self][0].username, alice.iceByPeer[chen.self][0].username);
  assert.deepEqual((await peer('alice')).iceByPeer, alice.iceByPeer);
  const [offerer, answerer] = alice.self < bob.self ? [['alice',alice],['bob',bob]] : [['bob',bob],['alice',alice]];
  await assert.rejects(peer(answerer[0], 'signal', {to: offerer[1].self,type:'answer',sdp}), {status:409});
  await peer(offerer[0], 'signal', {to:answerer[1].self,type:'offer',sdp});
  assert.equal((await peer(answerer[0])).signals[0].sdp, sdp);
  assert.deepEqual((await peer('chen')).signals, []);
  await peer(answerer[0], 'signal', {to:offerer[1].self,type:'answer',sdp});
  await peer('chen','leave');
  assert.ok(await peer('bob'));
  await peer('alice','leave');
  assert.equal(await peer('bob'), null);
  const next = await send('alice','start',{...request,requestId:randomUUID(),personIds:['bob']});
  await assert.rejects(peer('alice','leave'), {status:404});
  assert.equal((await send('bob')).call.id, next.call.id);
});

test('permissions, site, busy state and currently bound people govern availability', async () => {
  const {send, accounts, advance} = fixture();
  await send('bob'); await send('chen', 'presence', {siteId:'other'}); await send('dan','presence',{busy:true});
  assert.deepEqual((await send('alice')).contacts,['bob']);
  for (const ids of [['alice'],['chen'],['dan']]) {
    await assert.rejects(send('alice','start',{requestId:randomUUID(),personIds:ids}), {status:409});
  }
  await assert.rejects(send('alice','start',{requestId:randomUUID(),personIds:['bob','bob']}), {status:400});
  accounts.get('alice').canDial = false;
  await assert.rejects(send('alice','start',{requestId:randomUUID(),personIds:['bob']}), {status:403});
  accounts.get('alice').canDial = true;
  await send('alice','start',{requestId:randomUUID(),personIds:['bob']});
  accounts.get('alice').visible.delete('bob');
  assert.equal((await send('alice')).call,null);
  assert.equal((await send('bob')).call,null);
  accounts.get('alice').visible.set('bob','bob');
  advance(26000);
  assert.deepEqual((await send('alice')).contacts,[]);
});

test('decline, foreground exit, ring timeout and restarted service end the old call', async () => {
  const { send, advance } = fixture();
  const dial = async () => { await send('bob'); return (await send('alice','start',{requestId:randomUUID(),personIds:['bob']})).call; };
  let room = await dial();
  await send('bob','leave',{callId:room.id});
  assert.equal((await send('alice')).call,null);
  room = await dial();
  await send('bob','offline');
  assert.equal((await send('alice')).call,null);
  room = await dial();
  for (let i=0;i<3;i++) { advance(16000); await send('bob'); await send('alice'); }
  assert.equal((await send('bob')).call,null);
  await assert.rejects(fixture().send('bob','accept',{callId:room.id}),{status:404});
});

test('real HTTP gateway authenticates phone actions and advertises an available relay on identity only', async t => {
  const alice='a'.repeat(43), bob='b'.repeat(43);
  const auth = createServer((req,res) => {
    const name=req.headers['x-wearable-token']===alice?'alice':req.headers['x-wearable-token']===bob?'bob':null;
    res.setHeader('content-type','application/json');
    if(!name){res.writeHead(401);res.end('{}');return;}
    const data = req.url.endsWith('/identity') ? {id:name,name,personId:name,sites:[{id:'s1'}],permissionsBySite:{s1:['communications:voice']}}
      : {rows:[...roster.keys()].map(id=>({id,name:id}))};
    res.end(JSON.stringify(data));
  });
  auth.listen(0,'127.0.0.1'); await once(auth,'listening');
  const upstreamOrigin='http://127.0.0.1:'+auth.address().port;
  const gw=createWearGateway({testOnly:true,upstreamOrigin,phoneOptions:{identity:phoneIdentityReader(upstreamOrigin),relay:()=>[]}});
  gw.listen(0,'127.0.0.1'); await once(gw,'listening');
  t.after(async()=>{await Promise.all([gw,auth].map(s=>new Promise(r=>s.close(r))));});
  const base='http://127.0.0.1:'+gw.address().port+'/api/guardian/v1/mobile/';
  assert.equal((await fetch(base+'identity',{headers:{'x-wearable-token':alice}})).headers.get('x-wear-phone'),'1');
  const options=(token,siteId)=>({method:'POST',headers:{'content-type':'application/json','x-wearable-token':token},body:JSON.stringify({siteId,clientId:randomUUID()})});
  assert.equal((await fetch(base+'phone/presence',options('bad','s1'))).status,401);
  assert.equal((await fetch(base+'phone/presence',options(bob,'s1'))).status,200);
  assert.equal((await fetch(base+'phone/presence',options(alice,'other'))).status,403);
  assert.deepEqual((await (await fetch(base+'phone/presence',options(alice,'s1'))).json()).contacts,['bob']);
});
