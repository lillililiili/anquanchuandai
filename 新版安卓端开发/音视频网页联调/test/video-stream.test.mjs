import { test } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createBusinessLab, streamRandomVideo } from '../business-lab.mjs';

test('call media rejects missing or expired auth without system-login fallback', async t => {
  let logins = 0;
  const backend = http.createServer((req, res) => {
    if (req.url === '/login') logins++;
    res.writeHead(401, {'Content-Type':'application/json'}).end('{"code":401}');
  });
  await new Promise(resolve => backend.listen(0, '127.0.0.1', resolve));
  const handler = createBusinessLab({backendUrl:`http://127.0.0.1:${backend.address().port}`});
  const server = http.createServer((req,res) => handler(req,res,new URL(req.url, 'http://local')));
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(async () => { await new Promise(r => server.close(r)); await new Promise(r => backend.close(r)); });
  const url = `http://127.0.0.1:${server.address().port}/api/v1/lab/calls/45d640ce-a7bc-4dcd-991b-d4c0d11e4911/video/stream?deviceId=7`;
  assert.equal((await fetch(url)).status,401);
  assert.equal((await fetch(url,{headers:{Authorization:'Bearer expired','X-Site-Id':'1'}})).status,401);
  assert.equal(logins,0);
});

test('video keeps a fixed file across ranges and validates seek bounds', async t => {
  const previousCwd = process.cwd();
  const dir = fs.mkdtempSync(path.join(os.tmpdir(),'wear-video-test-'));
  fs.mkdirSync(path.join(dir,'video'));
  fs.writeFileSync(path.join(dir,'video','a.mp4'),Buffer.from('0123456789'));
  fs.writeFileSync(path.join(dir,'video','b.mp4'),Buffer.from('abcdefghij'));
  process.chdir(dir);
  const selection = {};
  const server = http.createServer((req,res) => streamRandomVideo(req,res,selection));
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(async () => {
    await new Promise(r => server.close(r));
    process.chdir(previousCwd);
    fs.rmSync(dir,{recursive:true,force:true});
  });
  const url = `http://127.0.0.1:${server.address().port}`;
  const first = await fetch(url,{headers:{Range:'bytes=0-3'}});
  assert.equal(first.status,206);
  const expected = first.headers.get('content-range');
  assert.equal(expected,'bytes 0-3/10');
  const body = await first.text();
  for(let i=0;i<8;i++) assert.equal(await (await fetch(url,{headers:{Range:'bytes=0-3'}})).text(),body);
  const suffix = await fetch(url,{headers:{Range:'bytes=-2'}});
  assert.equal(suffix.status,206);
  assert.equal(await suffix.text(),body === '0123' ? '89' : 'ij');
  for (const range of ['bytes=50-','bytes=9-2','bytes=a-b','bytes=0-1,4-5','bytes=-0']) {
    const response = await fetch(url,{headers:{Range:range}});
    assert.equal(response.status,416);
    assert.equal(response.headers.get('content-range'),'bytes */10');
  }
});
