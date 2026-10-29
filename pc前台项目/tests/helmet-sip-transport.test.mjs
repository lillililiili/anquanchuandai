import test from 'node:test';
import assert from 'node:assert/strict';
import * as SIP from 'sip.js';
import { helmetSipTransportOptions } from '../src/lib/helmet-sip-transport.js';

// Run the installed SIP.js UA, transport, REGISTER transaction and digest
// handling. Replace only the browser socket boundary: no network or device call.
async function registerThroughSocket(server) {
  const sockets=[], messages=[];
  const original=globalThis.WebSocket;
  class SyntheticSocket {
    listeners=new Map();
    constructor(url, protocol) { this.url=url; this.protocol=protocol; sockets.push(this); queueMicrotask(()=>this.emit('open',{})); }
    addEventListener(type, listener) { if(!this.listeners.has(type)) this.listeners.set(type,new Set()); this.listeners.get(type).add(listener); }
    emit(type,event) { for(const listener of this.listeners.get(type)||[]) listener(event); }
    send(message) {
      messages.push(message);
      const field=name=>message.match(new RegExp('^'+name+':\\s*(.+)$','mi'))?.[1]?.trim();
      const authenticated=!!field('Authorization'), expiresZero=/;expires=0(?:\s|$)/i.test(field('Contact')||'');
      const code=authenticated||expiresZero ? '200 OK' : '401 Unauthorized';
      const lines=['SIP/2.0 '+code, 'Via: '+field('Via'),'To: '+field('To')+';tag=fixture',
        'From: '+field('From'),'Call-ID: '+field('Call-ID'),'CSeq: '+field('CSeq')];
      if(code.startsWith('401')) lines.push('WWW-Authenticate: Digest realm="fixture.invalid",nonce="fixture-nonce",algorithm=MD5,qop="auth"');
      else lines.push('Contact: '+field('Contact'));
      lines.push('Content-Length: 0','','');
      queueMicrotask(()=>this.emit('message',{data:lines.join('\r\n')}));
    }
    close(code) { queueMicrotask(()=>this.emit('close',{code,wasClean:true})); }
  }
  globalThis.WebSocket=SyntheticSocket;
  const ua=new SIP.UserAgent({uri:SIP.UserAgent.makeURI('sip:fixture@fixture.invalid'),
    authorizationUsername:'fixture',authorizationPassword:'synthetic-only',
    transportOptions:{server,traceSip:false},logBuiltinEnabled:false,logConfiguration:false,
    ...helmetSipTransportOptions(SIP,server)});
  let registerer;
  try {
    await ua.start(); registerer=new SIP.Registerer(ua);
    await new Promise((resolve,reject)=>{
      const timer=setTimeout(()=>reject(Error('fixture registration timed out')),2000);
      registerer.stateChange.addListener(state=>{if(state===SIP.RegistererState.Registered){clearTimeout(timer);resolve();}});
      registerer.register({requestDelegate:{onReject:()=>{clearTimeout(timer);reject(Error('fixture rejected'));}}}).catch(reject);
    });
    assert.equal(registerer.state,SIP.RegistererState.Registered);
    assert.equal(messages.length,2,'one challenge followed by one authenticated REGISTER');
    assert.match(messages[1],/^Authorization: Digest /m);
    return {messages:[...messages], sockets:[...sockets], transportProtocol:ua.transport.protocol};
  } finally {
    try { if(registerer) await registerer.unregister(); await ua.stop(); }
    finally { globalThis.WebSocket=original; }
  }
}

test('real SIP.js registers through WSS socket using WS Via only for the known TLS proxy',async()=>{
  const server='wss://lingzhiaide.com/helmet-media/sip';
  const observed=await registerThroughSocket(server);
  assert.equal(observed.sockets[0].url,server);
  assert.equal(observed.sockets[0].protocol,'sip');
  assert.equal(observed.transportProtocol,'WS');
  for(const message of observed.messages) assert.match(message,/^Via: SIP\/2\.0\/WS /m);
});

test('other secure SIP endpoints keep the installed library WSS Via behavior',async()=>{
  const observed=await registerThroughSocket('wss://other.example/helmet-media/sip');
  assert.equal(observed.transportProtocol,'WSS');
  for(const message of observed.messages) assert.match(message,/^Via: SIP\/2\.0\/WSS /m);
  for(const server of ['ws://lingzhiaide.com/helmet-media/sip','wss://lingzhiaide.com/other',
    'wss://lingzhiaide.com:444/helmet-media/sip','wss://lingzhiaide.com/helmet-media/sip?x=1',
    'wss://other.example/helmet-media/sip','wss://user@lingzhiaide.com/helmet-media/sip']) {
    assert.deepEqual(helmetSipTransportOptions(SIP,server),{});
  }
});
