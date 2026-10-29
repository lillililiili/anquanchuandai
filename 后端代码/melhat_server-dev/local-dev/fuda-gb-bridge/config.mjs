import net from 'node:net';
export function configuration(env=process.env){
  const enabled=env.GB_ENABLED==='true';
  if(!enabled)return {enabled:false};
  const integer=(name,fallback,min,max)=>{const n=Number(env[name]??fallback);if(!Number.isInteger(n)||n<min||n>max)throw Error(`Invalid ${name}`);return n;};
  const ip=name=>{const v=env[name];if(net.isIP(v)!==4)throw Error(`${name} must be an explicit IPv4 address`);return v;};
  const secret=(name,min=32)=>{const v=env[name];if(!v||v.length<min||/[\r\n]/.test(v))throw Error(`Missing ${name}`);return v;};
  const id=name=>{if(!/^\d{20}$/.test(env[name]??''))throw Error(`Invalid ${name}`);return env[name];};
  const endpoint=(name)=>{const u=new URL(env[name]);if(!['https:','http:'].includes(u.protocol)||u.username||u.password||u.search||u.hash)throw Error(`Invalid ${name}`);if(u.protocol==='http:'&&!['127.0.0.1','localhost'].includes(u.hostname))throw Error(`${name}: HTTP is restricted to loopback; use HTTPS otherwise`);return u.href.replace(/\/$/,'');};
  let channels;try{channels=JSON.parse(env.GB_CHANNELS_JSON);}catch{throw Error('Invalid GB_CHANNELS_JSON');}
  if(!Array.isArray(channels)||!channels.length||channels.length>200)throw Error('Configure 1 to 200 helmet channels');
  const seen=new Set();for(const c of channels){if(!/^\d{20}$/.test(c.channelId??'')||!/[\s\S]/.test(c.name??'')||c.name.length>80||!/^[-A-Za-z0-9_]{1,100}$/.test(c.deviceId??'')||c.deviceType!=='HELMET'||seen.has(c.channelId))throw Error('Invalid helmet channel');seen.add(c.channelId);}
  const mediaPeers=(env.GB_MEDIA_PEERS??'').split(',').filter(Boolean);if(!mediaPeers.length||mediaPeers.some(x=>net.isIP(x)!==4))throw Error('GB_MEDIA_PEERS must contain explicit IPv4 addresses');
  const srs=new URL(env.GB_SRS_ORIGIN??'rtmp://127.0.0.1:1935');if(srs.protocol!=='rtmp:'||srs.username||srs.password||srs.search||srs.hash||srs.pathname)throw Error('Invalid GB_SRS_ORIGIN');
  const transport=env.GB_SIP_TRANSPORT??'UDP';if(!['UDP','TCP'].includes(transport))throw Error('Invalid GB_SIP_TRANSPORT');
  const config={enabled:true,transport,upperIp:ip('GB_UPPER_IP'),upperPort:integer('GB_UPPER_PORT',5060,1,65535),upperId:id('GB_UPPER_ID'),
    localId:id('GB_LOCAL_ID'),localIp:ip('GB_LOCAL_IP'),bindIp:env.GB_BIND_IP??'127.0.0.1',localPort:integer('GB_LOCAL_PORT',15060,1,65535),
    realm:env.GB_REALM||env.GB_UPPER_ID.slice(0,10),password:secret('GB_PASSWORD',1),username:env.GB_USERNAME||env.GB_LOCAL_ID,
    channels,mediaPeers,mediaMinPort:integer('GB_MEDIA_MIN_PORT',1024,1,65535),mediaMaxPort:integer('GB_MEDIA_MAX_PORT',65535,1,65535),
    mediaIp:ip('GB_MEDIA_IP'),rtpSourcePort:integer('GB_RTP_SOURCE_PORT',30000,1024,65000),requireAudio:env.GB_REQUIRE_AUDIO!=='false',registerSeconds:integer('GB_REGISTER_SECONDS',3600,60,86400),
    heartbeatSeconds:integer('GB_HEARTBEAT_SECONDS',60,10,3600),heartbeatFailures:integer('GB_HEARTBEAT_FAILURES',3,1,10),
    sourceTimeoutMs:integer('GB_SOURCE_TIMEOUT_MS',15000,1000,30000),ackTimeoutMs:integer('GB_ACK_TIMEOUT_MS',32000,1000,64000),
    maxSessionMs:integer('GB_MAX_SESSION_SECONDS',3600,60,86400)*1000,maxSessions:integer('GB_MAX_SESSIONS',8,1,100),
    javaOrigin:endpoint('GB_JAVA_ORIGIN'),javaSecret:secret('GB_JAVA_SECRET'),zlmOrigin:endpoint('GB_ZLM_ORIGIN'),zlmSecret:secret('GB_ZLM_SECRET'),
    srsOrigin:srs.href.replace(/\/$/,''),transactionMs:32000,t1:500,leaseRenewMs:20000,
    journal:env.GB_JOURNAL??'./data/active-sessions.json'};
  if(net.isIP(config.bindIp)!==4||config.mediaMinPort>config.mediaMaxPort||!/^[A-Za-z0-9._-]{1,100}$/.test(config.realm)||!/^[A-Za-z0-9._-]{1,100}$/.test(config.username)||config.javaSecret.length<32)throw Error('Invalid GB configuration');
  return config;
}
