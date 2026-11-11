import {createHash,createHmac,randomBytes} from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
const delay=(ms,signal)=>new Promise((resolve,reject)=>{const timer=setTimeout(done,ms);function done(){signal?.removeEventListener('abort',abort);resolve();}function abort(){clearTimeout(timer);reject(new MediaFault('GB_CANCELLED'));}if(signal?.aborted)abort();else signal?.addEventListener('abort',abort,{once:true});});
const scope=row=>({vhost:'__defaultVhost__',app:'fuda_gb',stream:row.leaseId});
const proxyKey=row=>`__defaultVhost__/fuda_gb/${row.leaseId}`;
const checkLease=row=>{if(!/^[-A-Za-z0-9_]{16,100}$/.test(row.leaseId??''))throw new MediaFault('GB_INVALID_LEASE');};
const cancelled=signal=>{if(signal?.aborted)throw new MediaFault('GB_CANCELLED');};
const codecName=track=>{
  const name=String(track.codec_id_name??({0:'H264',2:'AAC'}[track.codec_id]??'')).replace(/^Codec/i,'').toUpperCase();
  // ZLM's pinned release uses the RTP encoding name for AAC in getMediaInfo.
  return name==='MPEG4-GENERIC'?'AAC':name;
};

// The initial interop profile passes through the verified H.264/AAC source; it never manufactures audio.
function inspectTracks(info,requireAudio){
  const tracks=info.tracks??info.data?.tracks;
  if(!Array.isArray(tracks))return null;
  const video=tracks.find(t=>t.codec_type===0&&t.ready===true),audio=tracks.find(t=>t.codec_type===1&&t.ready===true);
  if(video&&codecName(video)!=='H264')throw new MediaFault('GB_UNSUPPORTED_VIDEO');
  if(audio&&codecName(audio)!=='AAC')throw new MediaFault('GB_UNSUPPORTED_AUDIO');
  return video&&(!requireAudio||audio)?{video:'H264',audio:audio?'AAC':null}:null;
}
export class MediaFault extends Error{constructor(code,status=503){super(code);this.code=code;this.status=status;}}
export function headers(secret,method,route,body=''){
  const time=String(Math.floor(Date.now()/1000)),nonce=randomBytes(18).toString('hex');
  const digest=createHash('sha256').update(body).digest('hex'),mac=createHmac('sha256',secret).update(`${time}\n${nonce}\n${method}\n${route}\n${digest}`).digest('hex');
  return {'Content-Type':'application/json','X-GB-Time':time,'X-GB-Nonce':nonce,'X-GB-Signature':mac};
}
export class SessionJournal{
  constructor(filename){this.filename=filename;this.rows={};if(filename&&fs.existsSync(filename)){this.rows=JSON.parse(fs.readFileSync(filename,'utf8'));if(!this.rows||typeof this.rows!=='object'||Array.isArray(this.rows)||Object.keys(this.rows).length>1000)throw Error('Invalid session journal');}}
  put(row){this.rows[row.leaseId]={leaseId:row.leaseId,proxyKey:row.proxyKey,stream:row.leaseId,ssrc:row.media?.ssrc};this.save();}
  remove(id){delete this.rows[id];this.save();}
  save(){
    if(!this.filename)return;
    fs.mkdirSync(path.dirname(this.filename),{recursive:true});const tmp=this.filename+'.tmp';
    const fd=fs.openSync(tmp,'w',0o600);try{fs.writeFileSync(fd,JSON.stringify(this.rows));fs.fsyncSync(fd);}finally{fs.closeSync(fd);}
    fs.renameSync(tmp,this.filename);
    // Linux deployment needs the rename durable as well. Windows cannot fsync a directory.
    if(process.platform!=='win32'){const dir=fs.openSync(path.dirname(this.filename),'r');try{fs.fsyncSync(dir);}finally{fs.closeSync(dir);}}
  }
}
export class MediaAdapter{
  constructor(config,{fetcher=fetch,journal}={}){this.config=config;this.fetch=fetcher;this.journal=journal??new SessionJournal(config.journal);}
  async json(url,options){
    let r;try{r=await this.fetch(url,{...options,redirect:'error',signal:AbortSignal.timeout(6000)});}catch{throw new MediaFault('GB_CONTROL_UNAVAILABLE');}
    const chunks=[];let size=0;
    try{for await(const chunk of r.body??[]){size+=chunk.length;if(size>1024*1024)throw new MediaFault('GB_CONTROL_RESPONSE_TOO_LARGE');chunks.push(chunk);}}
    catch(e){if(e instanceof MediaFault)throw e;throw new MediaFault('GB_CONTROL_UNAVAILABLE');}
    const bytes=Buffer.concat(chunks);
    let b;try{b=JSON.parse(bytes);}catch{throw new MediaFault('GB_CONTROL_INVALID_RESPONSE');}
    if(!b||typeof b!=='object'||Array.isArray(b))throw new MediaFault('GB_CONTROL_INVALID_RESPONSE');
    if(!r.ok)throw new MediaFault(/^GB_[A-Z_]+$/.test(b.error??'')?b.error:'GB_CONTROL_UNAVAILABLE',r.status);
    return b;
  }
  async java(method,route,input){const body=input===undefined?'':JSON.stringify(input),p='/internal/fuda-gb/v1'+route;
    const b=await this.json(this.config.javaOrigin+p,{method,headers:headers(this.config.javaSecret,method,p,body),...(body?{body}:{} )});
    if(b.code!==200||!b.data)throw new MediaFault('GB_CONTROL_INVALID_RESPONSE');return b.data;
  }
  async zlm(api,input){
    const body=new URLSearchParams({secret:this.config.zlmSecret,...input});
    const b=await this.json(`${this.config.zlmOrigin}/index/api/${api}`,{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body});
    if(b.code!==0){
      const error=new MediaFault('GB_MEDIA_OPERATION_FAILED');
      // This is ZLM RtmpPlayer's explicit first-media timeout, not a generic retry of
      // authentication, protocol, connection-refused or ambiguous HTTP failures.
      error.sourceStartupTimeout=api==='addStreamProxy'&&b.code===-1&&b.msg==='play rtmp timeout';
      throw error;
    }
    return b;
  }
  async device(channel){return this.java('GET',`/devices/${encodeURIComponent(channel.deviceId)}/status`);}
  async recover(){
    for(const row of Object.values(this.journal.rows)){
      if(!/^[-A-Za-z0-9_]{16,100}$/.test(row.leaseId))throw Error('Invalid recovery lease');
      if(!await this.release(row))throw Error('GB recovery cleanup unavailable');
    }
  }
  async cleanupOrphans(activeIds){for(const row of Object.values(this.journal.rows))if(!activeIds.has(row.leaseId))await this.release(row);}
  async createProxy(row,source,deadline,signal){
    for(let attempt=0;attempt<3;attempt++){
      cancelled(signal);const remaining=deadline-Date.now();
      if(remaining<250)throw new MediaFault('GB_SOURCE_TIMEOUT');
      try{return await this.zlm('addStreamProxy',{...scope(row),url:source,retry_count:0,timeout_sec:Math.min(5,remaining/1000),enable_hls:0,enable_mp4:0,enable_rtsp:0,enable_rtmp:1,enable_audio:1,add_mute_audio:0});}
      catch(error){
        cancelled(signal);
        if(!error.sourceStartupTimeout||attempt===2)throw error;
        // A new pull must never race an older one, even if its timeout reply was delayed.
        // Keep the journal until normal release/recovery confirms all resources are gone.
        await this.zlm('delStreamProxy',{key:proxyKey(row)});cancelled(signal);
        if(Date.now()+200>=deadline)throw new MediaFault('GB_SOURCE_TIMEOUT');
        await delay(200,signal);
      }
    }
  }
  async prepare(row,signal){
    checkLease(row);cancelled(signal);const deadline=Date.now()+this.config.sourceTimeoutMs;
    this.journal.put(row);
    let state=await this.java('PUT',`/leases/${row.leaseId}`,{deviceId:row.channel.deviceId});
    while(!state.publishing||!state.statusVerified){
      cancelled(signal);
      if(!state.online)throw new MediaFault('GB_DEVICE_OFFLINE');if(state.busy)throw new MediaFault('GB_DEVICE_BUSY',409);
      if(Date.now()>deadline)throw new MediaFault('GB_SOURCE_TIMEOUT');
      await delay(200,signal);state=await this.java('GET',`/leases/${row.leaseId}`);
    }
    cancelled(signal);
    if(!state.online)throw new MediaFault('GB_DEVICE_OFFLINE');if(state.busy)throw new MediaFault('GB_DEVICE_BUSY',409);
    if(!/^[A-Za-z0-9_-]{1,100}$/.test(state.streamId??'')||!/^[-A-Za-z0-9_.]{20,2048}$/.test(state.playToken??''))throw new MediaFault('GB_INVALID_SOURCE');
    // The input address is constructed exclusively from trusted operator config and a scoped ticket.
    // Neither the SIP URI nor SDP can select a pull URL or management endpoint.
    const source=`${this.config.srsOrigin}/helmet/${state.streamId}?token=${encodeURIComponent(state.playToken)}`;
    if(Date.now()>=deadline)throw new MediaFault('GB_SOURCE_TIMEOUT');
    // ZLM indexes proxies by vhost/app/stream. Persist that identity before creation so a lost
    // HTTP reply or process crash still allows deleting a proxy which has not published yet.
    row.proxyKey=proxyKey(row);this.journal.put(row);
    const result=await this.createProxy(row,source,deadline,signal);
    if(result.data?.key!==row.proxyKey)throw new MediaFault('GB_PROXY_NOT_CREATED');
    cancelled(signal);
    let ready=false;
    while(!ready&&Date.now()<deadline){
      cancelled(signal);
      try{const info=await this.zlm('getMediaInfo',{schema:'rtmp',...scope(row)});
        row.tracks=inspectTracks(info,this.config.requireAudio);ready=!!row.tracks;
      }catch(e){if(['GB_UNSUPPORTED_VIDEO','GB_UNSUPPORTED_AUDIO'].includes(e.code))throw e;}
      if(!ready)await delay(200,signal);
    }
    cancelled(signal);
    if(!ready)throw new MediaFault('GB_TRACKS_NOT_READY');
  }
  async start(row){const m=row.media;
    checkLease(row);cancelled(row.abort?.signal);
    const result=await this.zlm('startSendRtp',{...scope(row),ssrc:m.ssrc,dst_url:m.ip,dst_port:m.port,is_udp:m.tcp?0:1,src_port:row.localPort,pt:m.pt,use_ps:1});
    if(!Number.isInteger(result.local_port)||result.local_port!==row.localPort)throw new MediaFault('GB_RTP_PORT_MISMATCH');
    cancelled(row.abort?.signal);row.rtpStartedAt=Date.now();
  }
  async renew(row){checkLease(row);cancelled(row.abort?.signal);
    const state=await this.java('PUT',`/leases/${row.leaseId}`,{deviceId:row.channel.deviceId});if(!state.online||state.busy||!state.publishing||!state.statusVerified)throw new MediaFault('GB_SOURCE_LOST');
    cancelled(row.abort?.signal);
    const info=await this.zlm('getMediaInfo',{schema:'rtmp',...scope(row)});
    row.tracks=inspectTracks(info,this.config.requireAudio);if(!row.tracks)throw new MediaFault('GB_TRACKS_NOT_READY');
  }
  async release(row){
    checkLease(row);
    // Keep the journal on any failed release so startup recovery retries cleanup. No global stream close.
    const outcomes=await Promise.allSettled([
      this.zlm('stopSendRtp',{...scope(row),...(row.media?.ssrc||row.ssrc?{ssrc:row.media?.ssrc??row.ssrc}:{})}),
      this.zlm('delStreamProxy',{key:proxyKey(row)}),
      this.java('DELETE',`/leases/${row.leaseId}`)
    ]);
    // Removing the dedicated proxy also stops all of its senders; an already absent RTP sender is harmless.
    const released=outcomes[1].status==='fulfilled'&&outcomes[2].status==='fulfilled';
    if(released)this.journal.remove(row.leaseId);
    return released;
  }
}
