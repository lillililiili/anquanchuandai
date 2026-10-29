// Real M6811_58 ReportLocationApi: JSON {device_id,data:"seconds,lat,lon;..."}.
// Preserve collection timestamps. Java stores these as history, never live status.
export async function forwardBackup(request,response,query,config,send,fail) {
  if(query.get('ctl')!=='lowcaps'||query.get('act')!=='ca_backup_data'||[...query.keys()].some(k=>query.getAll(k).length!==1)
    ||(query.has('device_id')&&query.get('device_id')!==config.deviceId))return fail(response,400,'InvalidBackup');
  if(!/^application\/json(?:;|$)/i.test(request.headers['content-type']??'')||Number(request.headers['content-length']??0)>512*1024)return fail(response,413,'InvalidBackup');
  try {
    const chunks=[];let length=0;
    for await(const chunk of request){length+=chunk.length;if(length>512*1024)return fail(response,413,'TooLarge');chunks.push(chunk);}
    const input=JSON.parse(Buffer.concat(chunks));
    if(input.device_id!==config.deviceId||typeof input.data!=='string'||input.data.length>512*1024||Object.keys(input).some(k=>!['device_id','data'].includes(k)))return fail(response,400,'InvalidBackup');
    const points=input.data.split(';').filter(Boolean);
    if(!points.length||points.length>10000||points.some(p=>{
      const fields=p.split(',');return fields.length!==3||!/^\d{10}$/.test(fields[0])||fields.slice(1).some(x=>x.length>32||!Number.isFinite(Number(x)));
    }))return fail(response,400,'InvalidBackup');
    const upstream=await fetch(config.upstreamOrigin+'/api/index.php?ctl=lowcaps&act=ca_backup_data',{method:'POST',redirect:'error',
      body:JSON.stringify({device_id:config.deviceId,data:input.data}),headers:{'Content-Type':'application/json','Accept':'application/json'},signal:AbortSignal.timeout(30000)});
    if(!upstream.ok||Number(upstream.headers.get('content-length')??0)>65536)throw Error();
    const text=await upstream.text();if(text.length>65536)throw Error();const reply=JSON.parse(text);
    if(typeof reply.status!=='boolean')throw Error();return send(response,200,reply);
  }catch{return fail(response,502,'BackupUnavailable');}
}
