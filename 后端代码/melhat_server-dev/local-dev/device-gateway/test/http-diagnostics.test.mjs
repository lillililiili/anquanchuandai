import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { classifyHttpRoute,createHttpDiagnosticWriter } from '../http-diagnostics.mjs';

test('route classification emits only fixed labels, never path credentials or query values',()=>{
 const bootstrap='/secret-path/api/index.php',upload='/secret-path/api/upload';
 for(const [query,label] of [['ctl=device&act=check_stream&user_id=private','device/check_stream'],['ctl=config&act=get_config','config/get_config'],['ctl=report&act=add_image','report/add_image'],['ctl=image&act=save_image','media/photo'],['ctl=file&act=save_audio','media/audio'],['ctl=lowcaps&act=ca_backup_data','backup']])assert.equal(classifyHttpRoute(bootstrap+'?'+query,bootstrap,upload),label);
 assert.equal(classifyHttpRoute(upload+'?X-Progress-ID=private-md5',bootstrap,upload),'media/video');
 assert.equal(classifyHttpRoute('/other/private?token=secret',bootstrap,upload),'unknown');
 assert.equal(classifyHttpRoute(bootstrap+'?ctl=private&act=secret',bootstrap,upload),'unknown');
});

test('writer strips arbitrary fields and unrecognized enum values before writing',t=>{
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'http-diag-'));t.after(()=>fs.rmSync(dir,{recursive:true,force:true}));
 const write=createHttpDiagnosticWriter(dir);
 write({atUtc:'https://secret.invalid',method:'private-method',route:'private-route',status:415,declaredBodyBytes:12,latencyMs:3,errorCode:'private-error',uploadStage:'private-stage',url:'https://private.invalid?token=secret',headers:{Authorization:'secret'},body:'private-photo'});
 const contents=fs.readFileSync(path.join(dir,'http.jsonl'),'utf8'),row=JSON.parse(contents);
 assert.equal(row.method,'OTHER');assert.equal(row.route,'unknown');assert.equal(row.errorCode,'Other');assert.equal(row.uploadStage,'received');
 assert.ok(!contents.includes('secret'));assert.ok(!contents.includes('private'));
 assert.deepEqual(Object.keys(row).sort(),['atUtc','method','route','status','declaredBodyBytes','latencyMs','queryEmptySegment','errorCode','uploadStage'].sort());
});

test('rotation keeps at most three bounded local files',t=>{
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'http-diag-'));t.after(()=>fs.rmSync(dir,{recursive:true,force:true}));
 const write=createHttpDiagnosticWriter(dir,{maxBytes:512});
 for(let i=0;i<30;i++)write({method:'POST',route:'media/video',status:429,declaredBodyBytes:1024,latencyMs:i,errorCode:'Unavailable',uploadStage:'rate_limit'});
 assert.deepEqual(fs.readdirSync(dir).sort(),['http.1.jsonl','http.2.jsonl','http.jsonl']);
 for(const file of fs.readdirSync(dir)){assert.ok(fs.statSync(path.join(dir,file)).size<=512);for(const line of fs.readFileSync(path.join(dir,file),'utf8').trim().split('\n'))assert.equal(JSON.parse(line).status,429);}
});

test('unsafe file targets are refused without altering them',t=>{
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'http-diag-'));t.after(()=>fs.rmSync(dir,{recursive:true,force:true}));
 fs.mkdirSync(path.join(dir,'http.jsonl'));const write=createHttpDiagnosticWriter(dir);
 assert.throws(()=>write({method:'GET'}));assert.ok(fs.statSync(path.join(dir,'http.jsonl')).isDirectory());
});
