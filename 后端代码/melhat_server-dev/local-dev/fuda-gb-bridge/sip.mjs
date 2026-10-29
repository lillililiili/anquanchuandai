import {createHash,randomBytes} from 'node:crypto';
export const token=()=>randomBytes(12).toString('hex');
const aliases={v:'via',f:'from',t:'to',i:'call-id',l:'content-length',c:'content-type',m:'contact'};
export function parseMessage(buffer){
  if(buffer.length>65536)throw Error('SIP too large');
  const end=buffer.indexOf('\r\n\r\n');if(end<0)throw Error('Missing SIP headers');
  const lines=buffer.subarray(0,end).toString('utf8').split('\r\n'),start=lines.shift(),headers={};
  if(!/^(?:SIP\/2\.0 \d{3} [^\r\n]*|[A-Z]+ sip:[^\s]+ SIP\/2\.0)$/.test(start))throw Error('Invalid SIP start');
  for(const line of lines){const i=line.indexOf(':');if(i<1||/^[ \t]/.test(line))throw Error('Invalid SIP header');let key=line.slice(0,i).toLowerCase();key=aliases[key]??key;const value=line.slice(i+1).trim();if(headers[key]!==undefined&&!['via','record-route','route'].includes(key))throw Error('Duplicate SIP header');headers[key]=headers[key]?headers[key]+', '+value:value;}
  for(const key of ['via','from','to','call-id','cseq'])if(!headers[key]||headers[key].length>2048)throw Error('Missing SIP header');
  if(!/^\d{1,10} [A-Z]+$/.test(headers.cseq)||!/^\d{1,6}$/.test(headers['content-length']??''))throw Error('Invalid length or CSeq');
  const body=buffer.subarray(end+4);if(body.length!==Number(headers['content-length']))throw Error('SIP body length mismatch');
  return {start,headers,body,method:start.startsWith('SIP/')?null:start.split(' ')[0],status:start.startsWith('SIP/')?Number(start.split(' ')[1]):null,uri:start.split(' ')[1]};
}
export function frameLength(buffer){
  if(buffer.length>65536)throw Error('SIP frame too large');const end=buffer.indexOf('\r\n\r\n');if(end<0)return 0;
  const lengths=[...buffer.subarray(0,end).toString().matchAll(/^(?:Content-Length|l):\s*(\d+)\s*$/gim)];
  if(lengths.length!==1)throw Error('Invalid SIP TCP length');const n=end+4+Number(lengths[0][1]);if(n>65536)throw Error('SIP frame too large');return buffer.length>=n?n:0;
}
export function serialize(start,headers,body=''){
  const bytes=Buffer.isBuffer(body)?body:Buffer.from(body);
  const fields=Object.entries(headers).filter(([k])=>k.toLowerCase()!=='content-length');
  if(fields.some(([k,v])=>/[\r\n]/.test(k+v)))throw Error('Invalid SIP output header');
  return Buffer.concat([Buffer.from(start+'\r\n'+fields.map(([k,v])=>`${k}: ${v}`).join('\r\n')+`\r\nContent-Length: ${bytes.length}\r\n\r\n`),bytes]);
}
const reasons={100:'Trying',200:'OK',400:'Bad Request',403:'Forbidden',404:'Not Found',405:'Method Not Allowed',408:'Request Timeout',415:'Unsupported Media Type',480:'Temporarily Unavailable',481:'Call/Transaction Does Not Exist',486:'Busy Here',487:'Request Terminated',488:'Not Acceptable Here',500:'Server Internal Error',501:'Not Implemented',503:'Service Unavailable'};
export function response(request,status,extra={},body='',tag){
  const h=request.headers,to=h.to+(tag&&!/;tag=/.test(h.to)?`;tag=${tag}`:'');
  return serialize(`SIP/2.0 ${status} ${reasons[status]??'Error'}`,{Via:h.via,From:h.from,To:to,'Call-ID':h['call-id'],CSeq:h.cseq,...(h['record-route']?{'Record-Route':h['record-route']}:{}),...extra},body);
}
export const branch=m=>/;branch=([^;,\s]+)/i.exec(m.headers.via)?.[1];
export const tag=h=>/;tag=([^;,\s]+)/i.exec(h??'')?.[1];
export const user=h=>/sips?:([0-9]{20})@/i.exec(h??'')?.[1];
export function transactionKey(m){return `${m.headers['call-id']}|${m.headers.cseq}|${branch(m)}`;}
export function digest(challenge,{username,password,uri,method='REGISTER',expectedRealm}){
  if(!/^Digest\s/i.test(challenge??''))throw Error('Unsupported authentication');
  const fields={};for(const m of challenge.slice(7).matchAll(/([a-zA-Z]+)\s*=\s*(?:"([^"\r\n]*)"|([^,\s]+))/g))fields[m[1].toLowerCase()]=m[2]??m[3];
  if(fields.realm!==expectedRealm||!fields.nonce||fields.nonce.length>500||/["\\\r\n]/.test(fields.realm+fields.nonce+(fields.opaque??'')))throw Error('Invalid digest challenge');
  const algorithm=(fields.algorithm??'MD5').toUpperCase();if(!['MD5','SHA-256'].includes(algorithm))throw Error('Unsupported digest algorithm');
  if(fields.qop&&!fields.qop.split(',').map(x=>x.trim()).includes('auth'))throw Error('Unsupported digest qop');
  const hash=x=>createHash(algorithm==='MD5'?'md5':'sha256').update(x).digest('hex'),cnonce=token(),nc='00000001';
  const a1=hash(`${username}:${fields.realm}:${password}`),a2=hash(`${method}:${uri}`);
  const value=hash(fields.qop?`${a1}:${fields.nonce}:${nc}:${cnonce}:auth:${a2}`:`${a1}:${fields.nonce}:${a2}`);
  return `Digest username="${username}", realm="${fields.realm}", nonce="${fields.nonce}", uri="${uri}", response="${value}", algorithm=${algorithm}`+(fields.qop?`, qop=auth, nc=${nc}, cnonce="${cnonce}"`:'')+(fields.opaque?`, opaque="${fields.opaque}"`:'');
}
export const xml=value=>String(value).replace(/[<>&"']/g,x=>({'<':'&lt;','>':'&gt;','&':'&amp;','"':'&quot;',"'":'&apos;'}[x]));
export function queryXml(buffer){
  const head=buffer.subarray(0,100).toString(),encoding=/encoding=["'](GB2312|GBK|GB18030)["']/i.test(head)?'gb18030':'utf-8';
  const text=new TextDecoder(encoding,{fatal:true}).decode(buffer);
  if(text.length>16384||/<!DOCTYPE|<!ENTITY|<\?xml-stylesheet/i.test(text)||!/<Query>/.test(text))throw Error('Invalid query XML');
  const get=name=>{const matches=[...text.matchAll(new RegExp(`<${name}>([^<>]*)</${name}>`,'g'))];if(matches.length!==1)throw Error('Missing XML field');return matches[0][1];};
  const cmd=get('CmdType'),sn=get('SN'),deviceId=get('DeviceID');if(!/^\d{1,10}$/.test(sn)||!/^\d{20}$/.test(deviceId))throw Error('Invalid query values');return {cmd,sn,deviceId};
}
export function negotiateSdp(body,config){
  const lines=body.toString('utf8').split(/\r?\n/).filter(Boolean);if(lines.length>100||lines.some(x=>x.length>512))throw Error('SDP size');
  if(!lines.includes('v=0')||!lines.includes('t=0 0')||lines.filter(x=>x.startsWith('m=')).length!==1)throw Error('Only live video is supported');
  const match=/^m=video (\d{1,5}) (RTP\/AVP|TCP\/RTP\/AVP) ([\d ]+)$/.exec(lines.find(x=>x.startsWith('m='))??'');if(!match)throw Error('Unsupported media');
  const ip=/^c=IN IP4 ([0-9.]+)$/.exec(lines.filter(x=>x.startsWith('c=')).at(-1)??'')?.[1],port=Number(match[1]);
  if(!config.mediaPeers.includes(ip)||port<config.mediaMinPort||port>=config.mediaMaxPort||port>=65535)throw Error('Media destination denied');
  const map=lines.map(x=>/^a=rtpmap:(\d+) PS\/90000$/i.exec(x)).find(x=>x&&match[3].split(' ').includes(x[1]));if(!map||Number(map[1])>127)throw Error('PS payload required');
  const y=lines.filter(x=>x.startsWith('y='));if(y.length!==1||!/^y=[01]\d{9}$/.test(y[0])||Number(y[0].slice(2))>0xffffffff)throw Error('Invalid SSRC');
  if(lines.includes('a=sendonly')||lines.includes('a=inactive'))throw Error('Receiver required');
  const tcp=match[2].startsWith('TCP');if(tcp&&!lines.includes('a=setup:passive')&&!lines.includes('a=setup:actpass'))throw Error('TCP receiver must accept active sender');
  return {ip,port,tcp,pt:Number(map[1]),ssrc:String(Number(y[0].slice(2))),ssrcText:y[0].slice(2)};
}
export function answerSdp(config,media){
  return ['v=0',`o=${config.localId} 0 0 IN IP4 ${config.mediaIp}`,'s=Play',`c=IN IP4 ${config.mediaIp}`,'t=0 0',`m=video ${config.rtpSourcePort||9} ${media.tcp?'TCP/':''}RTP/AVP ${media.pt}`,'a=sendonly',`a=rtpmap:${media.pt} PS/90000`,...(media.tcp?['a=setup:active','a=connection:new']:[]),`y=${media.ssrcText}`,''].join('\r\n');
}
