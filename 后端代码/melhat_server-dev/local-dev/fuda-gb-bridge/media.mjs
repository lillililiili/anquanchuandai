import {createHash,createHmac,randomBytes} from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
const delay=(ms,signal)=>new Promise((resolve,reject)=>{const timer=setTimeout(done,ms);function done(){signal?.removeEventListener('abort',abort);resolve();}function abort(){clearTimeout(timer);reject(Error('CANCELLED'));}if(signal?.aborted)abort();else signal?.addEventListener('abort',abort,{once:true});});
export class MediaFault extends Error{constructor(code,status=503){super(code);this.code=code;this.status=status;}}
export function headers(secret,method,route,body=''){
  const time=String(Math.floor(Date.now()/1000)),nonce=randomBytes(18).toString('hex');
  const digest=createHash('sha256').update(body).digest('hex'),mac=createHmac('sha256',secret).update(`${time}\n${nonce}\n${method}\n${route}\n${digest}`).digest('hex');
  return {'Content-Type':'application/json','X-GB-Time':time,'X-GB-Nonce':nonce,'X-GB-Signature':mac};
}
export class SessionJournal{
  constructor(filename){this.filename=filename;this.rows={};if(filename&&fs.existsSync(filename)){this.rows=JSON.parse(fs.readFileSync(filename,'utf8'));if(!this.rows||Array.isArray(this.rows)||Object.keys(this.rows).length>1000)throw Error('Invalid session journal');}}
  put(row){this.rows[row.leaseId]={leaseId:row.leaseId,proxyKey:row.proxyKey,stream:row.leaseId,ssrc:row.media?.ssrc};this.save();}
  remove(id){delete this.rows[id];this.save();}
  save(){if(!this.filename)return;fs.mkdirSync(path.dirname(this.filename),{recursive:true});const tmp=this.filename+'.tmp';fs.writeFileSync(tmp,JSON.stringify(this.rows),{mode:0o600});fs.renameSync(tmp,this.filename);}
}
export class MediaAdapter{
  constructor(config,{fetcher=fetch,journal}={}){this.config=config;this.fetch=fetcher;this.journal=journal??new SessionJournal(config.journal);}
  async json(url,options){
    let r;try{r=await this.fetch(url,{...options,redirect:'error',signal:AbortSignal.timeout(6000)});}catch{throw new MediaFault('GB_CONTROL_UNAVAILABLE');}
    const bytes=Buffer.from(await r.arrayBuffer());if(bytes.length>1024*1024)throw new MediaFault('GB_CONTROL_RESPONSE_TOO_LARGE');
    let b;try{b=JSON.parse(bytes);}catch{throw new MediaFault('GB_CONTROL_INVALID_RESPONSE');}
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
    if(b.code!==0)throw new MediaFault('GB_MEDIA_OPERATION_FAILED');return b;
  }
  async device(channel){return this.java('GET',`/devices/${encodeURIComponent(channel.deviceId)}/status`);}
  async recover(){
    for(const row of Object.values(this.journal.rows)){
      if(!/^[-A-Za-z0-9_]{16,100}$/.test(row.leaseId))throw Error('Invalid recovery lease');
      if(!await this.release(row))throw Error('GB recovery cleanup unavailable');
    }
  }
  async cleanupOrphans(activeIds){for(const row of Object.values(this.journal.rows))if(!activeIds.has(row.leaseId))await this.release(row);}
  async prepare(row,signal){
    this.journal.put(row);
    let state=await this.java('PUT',`/leases/${row.leaseId}`,{deviceId:row.channel.deviceId});
    const deadline=Date.now()+this.config.sourceTimeoutMs;
    while(!state.publishing||!state.statusVerified){
      if(signal.aborted)throw new MediaFault('GB_CANCELLED');
      if(!state.online)throw new MediaFault('GB_DEVICE_OFFLINE');if(state.busy)throw new MediaFault('GB_DEVICE_BUSY',409);
      if(Date.now()>deadline)throw new MediaFault('GB_SOURCE_TIMEOUT');
      await delay(200,signal);state=await this.java('GET',`/leases/${row.leaseId}`);
    }
    if(signal.aborted)throw new MediaFault('GB_CANCELLED');
    if(!state.online)throw new MediaFault('GB_DEVICE_OFFLINE');if(state.busy)throw new MediaFault('GB_DEVICE_BUSY',409);
    if(!/^[A-Za-z0-9_-]{1,100}$/.test(state.streamId??'')||!/^[-A-Za-z0-9_.]{20,2048}$/.test(state.playToken??''))throw new MediaFault('GB_INVALID_SOURCE');
    // The input address is constructed exclusively from trusted operator config and a scoped ticket.
    // Neither the SIP URI nor SDP can select a pull URL or management endpoint.
    const source=`${this.config.srsOrigin}/helmet/${state.streamId}?token=${encodeURIComponent(state.playToken)}`;
    const result=await this.zlm('addStreamProxy',{vhost:'__defaultVhost__',app:'fuda_gb',stream:row.leaseId,url:source,retry_count:0,enable_hls:0,enable_mp4:0,enable_rtsp:0,enable_rtmp:1,enable_audio:1,add_mute_audio:0});
    row.proxyKey=result.data?.key;if(typeof row.proxyKey!=='string')throw new MediaFault('GB_PROXY_NOT_CREATED');this.journal.put(row);
    let ready=false;
    while(!ready&&Date.now()<deadline){
      if(signal.aborted)throw new MediaFault('GB_CANCELLED');
      try{const info=await this.zlm('getMediaInfo',{schema:'rtmp',vhost:'__defaultVhost__',app:'fuda_gb',stream:row.leaseId});
        const tracks=info.tracks??info.data?.tracks??[];
        const video=tracks.find(t=>t.codec_type===0&&t.ready!==false),audio=tracks.find(t=>t.codec_type===1&&t.ready!==false);
        if(video&&video.codec_id_name!=='H264')throw new MediaFault('GB_UNSUPPORTED_VIDEO');
        if(video&&(!this.config.requireAudio||audio))ready=true;
      }catch(e){if(e.code==='GB_UNSUPPORTED_VIDEO')throw e;}
      if(!ready)await delay(200,signal);
    }
    if(!ready)throw new MediaFault('GB_TRACKS_NOT_READY');
  }
  async start(row){const m=row.media;
    await this.zlm('startSendRtp',{vhost:'__defaultVhost__',app:'fuda_gb',stream:row.leaseId,ssrc:m.ssrc,dst_url:m.ip,dst_port:m.port,is_udp:m.tcp?0:1,src_port:row.localPort,pt:m.pt,use_ps:1});
  }
  async renew(row){const state=await this.java('PUT',`/leases/${row.leaseId}`,{deviceId:row.channel.deviceId});if(!state.online||state.busy||!state.publishing||!state.statusVerified)throw new MediaFault('GB_SOURCE_LOST');
    await this.zlm('getMediaInfo',{schema:'rtmp',vhost:'__defaultVhost__',app:'fuda_gb',stream:row.leaseId});
  }
  async release(row){
    // Keep the journal on any failed release so startup recovery retries cleanup. No global stream close.
    const outcomes=await Promise.allSettled([
      this.zlm('stopSendRtp',{vhost:'__defaultVhost__',app:'fuda_gb',stream:row.leaseId,...(row.media?.ssrc||row.ssrc?{ssrc:row.media?.ssrc??row.ssrc}:{})}),
      row.proxyKey?this.zlm('delStreamProxy',{key:row.proxyKey}):this.zlm('close_streams',{vhost:'__defaultVhost__',app:'fuda_gb',stream:row.leaseId,force:1}),
      this.java('DELETE',`/leases/${row.leaseId}`)
    ]);
    // Removing the dedicated proxy also stops all of its senders; an already absent RTP sender is harmless.
    const released=outcomes[1].status==='fulfilled'&&outcomes[2].status==='fulfilled';
    if(released)this.journal.remove(row.leaseId);
    return released;
  }
}
