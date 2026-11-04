import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROUTES = new Set(['config/get_config','device/check_stream','report/add_image','media/photo','media/video','media/audio','backup','unknown']);
const STAGES = new Set(['received','rate_limit','validation','receiving_body','body_received','forwarding_cloud','cloud_responded','durable_ack','forwarding_backend','backend_responded','acknowledged','client_closed']);
const CODES = new Set(['Unavailable','Unsupported','Busy','TooLarge','InvalidUpload','InvalidPhotoRequestId','DeviceMismatch','UploadUnavailable','InvalidBackup','BackupUnavailable','ClientDisconnected']);
const responses = new WeakMap();
const integer = value => Number.isSafeInteger(value) && value >= 0 ? value : null;

export function classifyHttpRoute(raw, bootstrapPath, uploadPath) {
  const separator = raw.indexOf('?'), pathname = separator < 0 ? raw : raw.slice(0,separator);
  if(pathname === uploadPath)return 'media/video';
  if(pathname !== bootstrapPath)return 'unknown';
  const query = new URLSearchParams(separator < 0 ? '' : raw.slice(separator+1));
  return ({'config/get_config':'config/get_config','device/check_stream':'device/check_stream','report/add_image':'report/add_image',
    'image/save_image':'media/photo','file/save_audio':'media/audio','lowcaps/ca_backup_data':'backup'})[`${query.get('ctl')}/${query.get('act')}`] ?? 'unknown';
}

export function markHttpStage(response, stage) {
  const row=responses.get(response);if(row && STAGES.has(stage))row.uploadStage=stage;
}
export function markHttpReply(response, code) {
  const row=responses.get(response);if(row && typeof code === 'string')row.errorCode=CODES.has(code)?code:'Other';
}

export function observeHttp(request,response,route,write) {
  if(typeof write !== 'function')return;
  const start=performance.now();
  const declared=request.headers['content-length'];
  const rawQuery=(request.url??'').split('?').slice(1).join('?');
  const row={method:['GET','POST','HEAD','OPTIONS'].includes(request.method)?request.method:'OTHER',route:ROUTES.has(route)?route:'unknown',
    declaredBodyBytes:declared == null ? null : integer(Number(declared)),queryEmptySegment:rawQuery.length>0&&rawQuery.split('&').some(part=>part===''),uploadStage:'received',errorCode:null};
  responses.set(response,row);
  let emitted=false;
  const finish=()=>{
    if(emitted)return;emitted=true;
    const completed=response.writableFinished;
    if(!completed){row.uploadStage='client_closed';row.errorCode='ClientDisconnected';}
    try { write({atUtc:new Date().toISOString(),...row,status:completed?response.statusCode:0,latencyMs:Math.max(0,Math.round(performance.now()-start))}); }
    catch { /* Diagnostics never alter firmware acknowledgement or device forwarding. */ }
    responses.delete(response);
  };
  response.once('finish',finish);response.once('close',finish);
}

// Fixed schema and three bounded files. No URLs, query values, headers, bodies,
// firmware messages, or raw errors reach the writer, even through a caller error.
export function createHttpDiagnosticWriter(location,{maxBytes=1024*1024}={}) {
  const directory=path.resolve(location instanceof URL?fileURLToPath(location):location);
  if(!Number.isSafeInteger(maxBytes)||maxBytes<512||maxBytes>1024*1024)throw Error('Invalid diagnostic limit');
  if(fs.existsSync(path.dirname(directory))&&fs.lstatSync(path.dirname(directory)).isSymbolicLink())throw Error('Diagnostic directory must be local');
  fs.mkdirSync(directory,{recursive:true,mode:0o700});
  if(fs.lstatSync(directory).isSymbolicLink())throw Error('Diagnostic directory must be local');
  const files=['http.jsonl','http.1.jsonl','http.2.jsonl'].map(name=>path.join(directory,name));
  const check=filename=>{if(fs.existsSync(filename)&&(!fs.lstatSync(filename).isFile()||fs.lstatSync(filename).isSymbolicLink()))throw Error('Diagnostic target must be a regular file');};
  return input=>{
    const timestamp=typeof input.atUtc==='string'&&/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(input.atUtc)?input.atUtc:new Date().toISOString();
    const row={atUtc:timestamp,method:['GET','POST','HEAD','OPTIONS','OTHER'].includes(input.method)?input.method:'OTHER',
      route:ROUTES.has(input.route)?input.route:'unknown',status:Number.isInteger(input.status)&&input.status>=100&&input.status<=599?input.status:0,
      declaredBodyBytes:integer(input.declaredBodyBytes),latencyMs:integer(input.latencyMs),queryEmptySegment:input.queryEmptySegment===true,
      errorCode:input.errorCode == null?null:CODES.has(input.errorCode)?input.errorCode:'Other',uploadStage:STAGES.has(input.uploadStage)?input.uploadStage:'received'};
    const line=JSON.stringify(row)+'\n';for(const file of files)check(file);
    if(fs.existsSync(files[0])&&fs.statSync(files[0]).size+Buffer.byteLength(line)>maxBytes){
      if(fs.existsSync(files[2]))fs.unlinkSync(files[2]);
      if(fs.existsSync(files[1]))fs.renameSync(files[1],files[2]);
      fs.renameSync(files[0],files[1]);
    }
    fs.appendFileSync(files[0],line,{encoding:'utf8',mode:0o600,flag:fs.constants.O_APPEND|fs.constants.O_CREAT|fs.constants.O_WRONLY|(fs.constants.O_NOFOLLOW??0)});
  };
}
