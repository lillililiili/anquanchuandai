import test from 'node:test';
import assert from 'node:assert/strict';
import { blobPut } from '../src/lib/files.js';

test('photo upload requires the server to acknowledge the exact file', async t => {
  t.mock.method(globalThis, 'fetch', async () => new Response(JSON.stringify({ code: 500, msg: '服务暂不可用' })));
  const previous = Object.getOwnPropertyDescriptor(globalThis, 'sessionStorage');
  Object.defineProperty(globalThis, 'sessionStorage', { configurable: true, value: { getItem: () => 'fixture' } });
  t.after(() => {
    if (previous) Object.defineProperty(globalThis, 'sessionStorage', previous);
    else delete globalThis.sessionStorage;
  });
  const put = () => blobPut('upload-1', new Blob(['picture'], { type: 'image/png' }));
  await assert.rejects(put(), /服务暂不可用/);
  fetch.mock.mockImplementation(async () => new Response('{"ok":true,"id":"upload-2"}'));
  await assert.rejects(put(), /响应无效/);
  fetch.mock.mockImplementation(async () => new Response('{"ok":true,"id":"upload-1"}'));
  assert.equal(await put(), 'upload-1');
});
