import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import { signedHeaders, signedDigestHeaders } from '../helmet-media/auth.mjs';
import { spool } from '../helmet-media/spool.mjs';

// Owner is fixed by the registered secret entry, never caller headers.
// Firmware can delete its local video after ACK: acknowledge durable storage only.
export function createMediaUpload(config, fetchMedia = fetch) {
  let active = 0;
  return async (request, response, query, send, fail, video = false) => {
    if (!config.mediaControlOrigin) return fail(response, 501, 'Unsupported');
    const action = `${query.get('ctl')}/${query.get('act')}`;
    const binding = action === 'report/add_image';
    const streamCheck=action==='device/check_stream';
    const kind = video ? 'video' : { 'image/save_image': 'photo', 'file/save_audio': 'audio' }[action];
    const keys = new Set(['ctl','act','device_id','app_version','ic','ca_ver',...(video?['X-Progress-ID']:[]),...(streamCheck?['user_id']:[])]);
    if ((!kind && !binding && !streamCheck) || [...query.keys()].some(k=>!keys.has(k)||query.getAll(k).length!==1)
      || [...query.values()].some(v=>v.length>256||/[\u0000-\u001f\u007f-\u009f]/.test(v))
      || (query.has('device_id')&&query.get('device_id')!==config.deviceId)
      || (video && (query.get('device_id')!==config.deviceId || !/^[A-Za-z0-9_-]{8,80}$/.test(query.get('X-Progress-ID')??'')))) return fail(response,400,'InvalidUpload');
    if(active>=2) return fail(response,429,'Busy');
    const max=binding||streamCheck?8192:256*1024*1024;
    if(Number(request.headers['content-length']??0)>max) return fail(response,413,'TooLarge');
    if(!binding && !streamCheck && !/^multipart\/form-data;\s*boundary=/i.test(request.headers['content-type']??'')) return fail(response,415,'InvalidUpload');
    active++;let saved,body;
    try {
      let controlPath,headers;
      if(binding||streamCheck) {
        const chunks=[];let count=0;for await(const chunk of request){count+=chunk.length;if(count>max)throw Error('Too large');chunks.push(chunk);}
        const input=streamCheck?{}:JSON.parse(Buffer.concat(chunks));
        if(binding&&input.device_id!==config.deviceId) return fail(response,403,'DeviceMismatch');
        body=Buffer.from(JSON.stringify({deviceId:config.deviceId,...(binding?{imageUrl:input.image_url,latitude:input.x_point,longitude:input.y_point}:{})}));
        controlPath='/helmet-media/control/v1/'+(binding?'photo-bind':'device-stream-status');headers={...signedHeaders(config.mediaSigningKey,'POST',controlPath,body),'Content-Type':'application/json'};
      } else {
        saved=await spool(request,path.join(path.dirname(fileURLToPath(import.meta.url)),'.local/upload-temp'),max);
        controlPath=`/helmet-media/control/v1/device-upload?deviceId=${config.deviceId}&kind=${kind}${video?'&progressId='+encodeURIComponent(query.get('X-Progress-ID')):''}`;
        body=fs.createReadStream(saved.filename);body.on('error',()=>{});
        headers={...signedDigestHeaders(config.mediaSigningKey,'POST',controlPath,saved.digest),'Content-Type':request.headers['content-type'],'Content-Length':String(saved.length)};
      }
      const upstream=await fetchMedia(config.mediaControlOrigin+controlPath,{method:'POST',body,duplex:'half',redirect:'error',headers,signal:AbortSignal.timeout(240000)});
      if(!upstream.ok || Number(upstream.headers.get('content-length')??0)>65536)throw Error('Upload unavailable');
      const text=await upstream.text();if(text.length>65536)throw Error('Invalid response');
      const result=JSON.parse(text),asset=result.data;
      if(streamCheck){if(result.code!==200||asset?.statusVerified!==true)throw Error('Unverified stream');return send(response,200,{status:asset.publishing,msg:asset.publishing?'正在推流':'未推流',data:{push:asset.publishing}});}
      if(result.code!==200 || asset?.status!=='ready')throw Error('Storage failed');
      if(binding)return send(response,200,{status:true,msg_code:'AddSucc',msg:'添加成功',data:[]});
      if(asset.deviceId!==config.deviceId||asset.kind!==kind||!asset.url?.startsWith(config.mediaControlOrigin+'/helmet-media/files/'))throw Error('Invalid owner');
      return send(response,200,{status:true,msg_code:video?'Success':'UploadSucc',msg:'上传成功',data:{url:asset.url,whole_url:asset.url}});
    }catch{return fail(response,502,'UploadUnavailable');}
    finally{active--;if(body?.destroy)await new Promise(resolve=>{body.once('close',resolve);body.destroy();if(body.closed)resolve();});if(saved)await fs.promises.unlink(saved.filename).catch(()=>{});}
  };
}
