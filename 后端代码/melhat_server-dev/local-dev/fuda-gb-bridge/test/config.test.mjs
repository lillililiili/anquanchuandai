import test from 'node:test';
import assert from 'node:assert/strict';
import {configuration} from '../config.mjs';

function settings(overrides={}){
  return {GB_ENABLED:'true',GB_UPPER_ID:'34020000001320000001',GB_UPPER_IP:'127.0.0.1',GB_UPPER_PORT:'30006',
    GB_LOCAL_ID:'34020000002000000002',GB_LOCAL_IP:'127.0.0.1',GB_PASSWORD:'fixture-password',
    GB_MEDIA_IP:'127.0.0.1',GB_MEDIA_PEERS:'127.0.0.1',GB_MEDIA_MIN_PORT:'30010',GB_MEDIA_MAX_PORT:'30050',
    GB_JAVA_ORIGIN:'http://127.0.0.1:18084',GB_JAVA_SECRET:'fixture-java-secret-00000000000000',
    GB_ZLM_ORIGIN:'http://127.0.0.1:18194',GB_ZLM_SECRET:'fixture-zlm-secret-000000000000000',
    GB_CHANNELS_JSON:JSON.stringify([{channelId:'34020000001320000002',deviceId:'fixture-helmet',deviceType:'HELMET',name:'安全帽'}]),
    ...overrides};
}

test('GB2312 partner configuration preserves its explicit SIP and inclusive RTP range',()=>{
  const c=configuration(settings({GB_CHARSET:'GB2312'}));
  assert.equal(c.charset,'GB2312');assert.equal(c.transport,'UDP');assert.equal(c.upperPort,30006);
  assert.deepEqual([c.mediaMinPort,c.mediaMaxPort],[30010,30050]);
  assert.equal(c.username,c.localId);assert.equal(c.channels[0].name,'安全帽');
  assert.equal(configuration(settings()).charset,'UTF-8');
});

test('unknown XML charset and duplicate platform/channel identities cannot start signaling',()=>{
  assert.throws(()=>configuration(settings({GB_CHARSET:'UTF-16'})),/GB_CHARSET/);
  assert.throws(()=>configuration(settings({GB_LOCAL_ID:'34020000001320000001'})),/distinct/);
  assert.throws(()=>configuration(settings({GB_CHANNELS_JSON:JSON.stringify([{channelId:'34020000001320000001',deviceId:'fixture-helmet',deviceType:'HELMET',name:'安全帽'}])})),/distinct/);
});

test('extra TCP media ports are empty by default and require explicit individual valid ports',()=>{
  assert.deepEqual(configuration(settings()).mediaExtraTcpPorts,[]);
  const c=configuration(settings({GB_MEDIA_EXTRA_TCP_PORTS:'30003'}));
  assert.deepEqual(c.mediaExtraTcpPorts,[30003]);assert.deepEqual([c.mediaMinPort,c.mediaMaxPort],[30010,30050]);
  assert.deepEqual(configuration(settings({GB_MEDIA_EXTRA_TCP_PORTS:' 30003,30003 '})).mediaExtraTcpPorts,[30003]);
  for(const value of ['30003-30009','30003,','0','65535','30003.0','3e4','-1','unknown']){
    assert.throws(()=>configuration(settings({GB_MEDIA_EXTRA_TCP_PORTS:value})),/Invalid GB_MEDIA_EXTRA_TCP_PORTS/);
  }
});
