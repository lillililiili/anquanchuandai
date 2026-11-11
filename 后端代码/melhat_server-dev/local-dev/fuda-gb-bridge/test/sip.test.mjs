import test from 'node:test';
import assert from 'node:assert/strict';
import {encodeXml,queryXml,serialize,parseMessage,frameLength,negotiateSdp} from '../sip.mjs';

const query='<Query><CmdType>Catalog</CmdType><SN>1</SN><DeviceID>34020000002000000002</DeviceID></Query>';
const headers={Via:'SIP/2.0/UDP 127.0.0.1:5060;branch=z9hG4bKtest',From:'<sip:34020000002000000001@3402000000>;tag=test',To:'<sip:34020000002000000002@3402000000>','Call-ID':'test',CSeq:'1 MESSAGE'};

test('UTF-8 and GB2312 XML serialization preserve characters with correct byte counts',()=>{
  const document='<Response><Name>安全帽 &amp; 一号</Name></Response>';
  const utf8=encodeXml(document,'UTF-8'),gb=encodeXml(document,'GB2312');
  assert.match(utf8.body.toString('utf8'),/<Name>安全帽 &amp; 一号<\/Name>/);
  assert.match(gb.body.toString('ascii'),/<Name>&#23433;&#20840;&#24125; &amp; &#19968;&#21495;<\/Name>/);
  assert.ok(gb.body.every(b=>b<128));
  for(const encoded of [utf8,gb]){
    const message=parseMessage(serialize('MESSAGE sip:34020000002000000002@3402000000 SIP/2.0',{...headers,'Content-Type':encoded.contentType},encoded.body));
    assert.equal(Number(message.headers['content-length']),encoded.body.length);
    assert.deepEqual(message.body,encoded.body);
  }
  assert.throws(()=>encodeXml(document,'UTF-16'));
  assert.throws(()=>encodeXml('<Response>\u0000</Response>','GB2312'));
});

test('GB2312 query decoding handles real Chinese bytes and rejects unknown or conflicting encodings',()=>{
  const bytes=Buffer.concat([Buffer.from('<?xml version="1.0" encoding="GB2312"?><Query><Comment>'),Buffer.from([0xb0,0xb2,0xc8,0xab]),Buffer.from('</Comment>'+query.slice('<Query>'.length))]);
  assert.deepEqual(queryXml(bytes,'Application/MANSCDP+xml; charset=GB2312'),{cmd:'Catalog',sn:'1',deviceId:'34020000002000000002'});
  assert.throws(()=>queryXml(bytes,'Application/MANSCDP+xml; charset=UTF-8'));
  assert.throws(()=>queryXml(Buffer.from('<?xml version="1.0" encoding="ISO-8859-1"?>'+query)));
  assert.throws(()=>queryXml(Buffer.from(query),'Application/MANSCDP+xml; charset=UTF-16'));
  assert.throws(()=>queryXml(Buffer.from(query),'Application/MANSCDP+xml; charset=UTF-8; charset=UTF-8'));
  assert.throws(()=>queryXml(Buffer.from('<Other>'+query+'</Other>')));
});

test('TCP frame limit applies per message, including coalesced frames',()=>{
  const one=serialize('MESSAGE sip:34020000002000000002@3402000000 SIP/2.0',headers,'x'.repeat(40000));
  const joined=Buffer.concat([one,one]);assert.ok(joined.length>65536);
  assert.equal(frameLength(joined),one.length);assert.equal(frameLength(joined.subarray(one.length)),one.length);
  assert.equal(frameLength(one.subarray(0,one.length-1)),0);
  assert.throws(()=>frameLength(Buffer.from('x'.repeat(65537))));
  assert.throws(()=>frameLength(serialize('MESSAGE sip:34020000002000000002@3402000000 SIP/2.0',headers,'x'.repeat(65537))));
});

const offer=(port=30050,attributes='a=recvonly\r\n',transport='RTP/AVP')=>Buffer.from(`v=0\r\no=34020000002000000001 0 0 IN IP4 127.0.0.1\r\ns=Play\r\nc=IN IP4 127.0.0.1\r\nt=0 0\r\nm=video ${port} ${transport} 96\r\na=rtpmap:96 PS/90000\r\n${attributes}y=0100000001\r\n`);
const config={mediaPeers:['127.0.0.1'],mediaMinPort:30010,mediaMaxPort:30050};

test('RTP range includes both explicitly configured boundaries',()=>{
  assert.equal(negotiateSdp(offer(30010),config).port,30010);
  assert.equal(negotiateSdp(offer(30050),config).port,30050);
  assert.throws(()=>negotiateSdp(offer(30009),config));assert.throws(()=>negotiateSdp(offer(30051),config));
});

test('conflicting SDP direction and TCP setup attributes cannot negotiate a sender',()=>{
  assert.throws(()=>negotiateSdp(offer(30010,'a=recvonly\r\na=sendonly\r\n'),config));
  assert.throws(()=>negotiateSdp(offer(30010,'a=recvonly\r\na=setup:passive\r\na=setup:active\r\n','TCP/RTP/AVP'),config));
  const withSession=offer(30010).toString().replace('m=video','a=sendonly\r\nm=video');
  assert.equal(negotiateSdp(Buffer.from(withSession),config).port,30010,'media-level receive direction overrides session-level direction');
});

test('confirmed TCP receive port is an exact peer-scoped exception, never an expanded UDP or port range',()=>{
  const allowed={...config,mediaExtraTcpPorts:[30003]};
  const tcp=port=>Buffer.from(offer(port,'a=recvonly\r\na=setup:passive\r\n','TCP/RTP/AVP').toString().replace('TCP/RTP/AVP 96','TCP/RTP/AVP 96 97 98 99'));
  assert.throws(()=>negotiateSdp(tcp(30003),config),/Media destination denied/);
  const selected=negotiateSdp(tcp(30003),allowed);
  assert.equal(selected.tcp,true);assert.equal(selected.port,30003);assert.equal(selected.pt,96);
  assert.throws(()=>negotiateSdp(offer(30003),allowed),/Media destination denied/);
  for(const port of [30001,30002,30004,30005,30006,30007,30008,30009,30051]){
    assert.throws(()=>negotiateSdp(tcp(port),allowed),/Media destination denied/);
  }
  assert.throws(()=>negotiateSdp(Buffer.from(tcp(30003).toString().replace('c=IN IP4 127.0.0.1','c=IN IP4 192.0.2.10')),allowed),/Media destination denied/);
  for(const port of [30010,30050]){
    assert.equal(negotiateSdp(tcp(port),allowed).port,port);
    assert.equal(negotiateSdp(offer(port),allowed).port,port);
  }
});
