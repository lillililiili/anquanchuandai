import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { parse, compileScript } from '@vue/compiler-sfc';
import * as Vue from 'vue';
import { mediaUrl } from '../src/lib/helmet-media.js';
import * as previewSource from '../src/lib/media-preview-source.js';

const file = {
  id: 'video-1', deviceId: 'helmet-1', siteId: 'site-1', station: 'S1',
  source: 'DIRECT_HELMET', kind: 'video', title: '现场录像',
  url: 'https://media.example.test/helmet-media/files/video-1?token=first-ticket',
};

async function preview(media = file) {
  const raw = await readFile(new URL('../src/components/domain/MediaImage.vue', import.meta.url), 'utf8');
  const { descriptor } = parse(raw);
  const code = compileScript(descriptor, { id: 'media-image-behavior' }).content;
  const requests = [], created = [], revoked = [], unmounts = [];
  const props = Vue.reactive({ media: media ? { ...media } : null });
  const db = Vue.reactive({ demoMode: false });
  const modules = {
    vue: { ...Vue, onUnmounted(callback) { unmounts.push(callback); } },
    '@/lib/files': { blobGet(id) { return new Promise((resolve, reject) => requests.push({ id, resolve, reject })); } },
    '@/lib/helmet-media': { mediaUrl },
    '@/lib/media-preview-source': previewSource,
    '@/mock/runtime': { db },
  };
  const compiled = code.replace(/^import\s+([\s\S]*?)\s+from\s+(['"])([^'"]+)\2;?\s*$/gm, (_, names, _quote, from) => {
    assert.ok(modules[from], `unexpected dependency: ${from}`);
    const binding = names.trim().startsWith('{') ? names.replace(/\bas\b/g, ':') : `{ default: ${names} }`;
    return `const ${binding} = modules[${JSON.stringify(from)}];\n`;
  }).replace('export default', 'return');
  class TestURL extends URL {
    static createObjectURL(blob) {
      const url = `blob:test-preview/${created.length + 1}`;
      created.push({ blob, url });
      return url;
    }
    static revokeObjectURL(url) { revoked.push(url); }
  }
  const component = new Function('modules', 'URL', compiled)(modules, TestURL);
  const scope = Vue.effectScope();
  const instance = scope.run(() => component.setup(props, { expose() {} }));
  const transitions = [];
  scope.run(() => Vue.watch(instance.src, value => transitions.push(value), { flush: 'sync' }));
  const flush = async () => { await Promise.resolve(); await Vue.nextTick(); await Promise.resolve(); };
  let disposed = false;
  function dispose() {
    if (disposed) return;
    disposed = true;
    scope.stop();
    for (const callback of unmounts) callback();
  }
  return { instance, props, db, requests, created, revoked, transitions, flush, dispose };
}

test('polling the same helmet file preserves its loaded URL and render identity through ticket renewal', async t => {
  const f = await preview(); t.after(f.dispose);
  const generation = f.instance.renderGeneration.value;
  f.props.media = { ...file, title: '更新后的名称', url: file.url.replace('first-ticket', 'renewed-ticket'), createdAt: '2026-11-03T05:00:00Z' };
  await f.flush();
  assert.equal(f.instance.src.value, file.url, 'already displayed frames keep the original loaded source');
  assert.equal(f.instance.renderGeneration.value, generation, 'polling must not remount the media element');
  assert.deepEqual(f.transitions, [], 'polling must not temporarily clear the preview');
  f.props.media = { ...f.props.media, title: '又一次元数据刷新' };
  await f.flush();
  assert.deepEqual(f.transitions, []);
});

test('switching files or authorization context changes source, and revoked media clears immediately', async t => {
  const f = await preview(); t.after(f.dispose);
  const initialGeneration = f.instance.renderGeneration.value;
  const next = { ...file, id: 'video-2', url: file.url.replace('video-1', 'video-2') };
  f.props.media = next;
  await f.flush();
  assert.equal(f.instance.src.value, next.url);
  assert.ok(f.instance.renderGeneration.value > initialGeneration);
  const fileGeneration = f.instance.renderGeneration.value;
  f.props.media = { ...next, deviceId: 'helmet-2', siteId: 'site-2', station: 'S2' };
  await f.flush();
  assert.ok(f.instance.renderGeneration.value > fileGeneration, 'an authorization-context change cannot reuse the old element');
  f.props.media = null;
  await f.flush();
  assert.equal(f.instance.src.value, '');
  assert.equal(f.transitions.at(-1), '');
});

test('only the recognized helmet file ticket is ignored when deciding whether a remote source changed', async t => {
  for (const original of [
    { ...file, source: 'EXTERNAL' },
    { ...file, url: 'https://media.example.test/other/video-1?token=first-ticket' },
  ]) {
    const f = await preview(original); t.after(f.dispose);
    const replacement = original.url.replace('first-ticket', 'different-resource');
    f.props.media = { ...original, url: replacement };
    await f.flush();
    assert.equal(f.instance.src.value, replacement, 'unknown sources may use token as part of their resource identity');
  }
  const f = await preview(); t.after(f.dispose);
  const variant = `${file.url}&variant=thumbnail`;
  f.props.media = { ...file, url: variant };
  await f.flush();
  assert.equal(f.instance.src.value, variant, 'a different asset variant is a genuine source change');
  const otherOrigin = variant.replace('media.example.test', 'other.example.test');
  f.props.media = { ...file, url: otherOrigin };
  await f.flush();
  assert.equal(f.instance.src.value, otherOrigin);
});

test('removing or emptying a helmet access ticket never retains the previously authorized preview', async t => {
  for (const replacement of [file.url.split('?')[0], file.url.replace('first-ticket', '')]) {
    const f = await preview(); t.after(f.dispose);
    const generation = f.instance.renderGeneration.value;
    f.props.media = { ...file, url: replacement };
    await f.flush();
    assert.equal(f.instance.src.value, replacement, 'the source must no longer contain the preceding access ticket');
    assert.ok(f.instance.renderGeneration.value > generation, 'removing authorization must replace the old media element');
    assert.ok(f.transitions.includes(''), 'the old authorized frame is cleared before loading the changed source');
  }
});

test('failed remote previews show failure and explicit retry uses the newest authorized ticket', async t => {
  const f = await preview(); t.after(f.dispose);
  f.instance.onError();
  assert.ok(f.instance.error.value, 'a failed image or video must have an explicit failure state');
  assert.equal(f.instance.src.value, '');
  const renewed = file.url.replace('first-ticket', 'latest-ticket');
  f.props.media = { ...file, url: renewed };
  await f.flush();
  assert.ok(f.instance.error.value, 'background polling must not create an automatic failing reload loop');
  assert.equal(f.instance.src.value, '');
  await f.instance.retry();
  assert.equal(f.instance.src.value, renewed, 'retry must use the current signed URL, never the stale failed ticket');
  assert.equal(Boolean(f.instance.error.value), false);
});

test('an invalid remote URL does not leave the preceding file visible', async t => {
  const f = await preview(); t.after(f.dispose);
  f.props.media = { ...file, id: 'invalid-file', url: 'javascript:alert(1)' };
  await f.flush();
  assert.equal(f.instance.src.value, '');
  assert.ok(f.instance.error.value || f.instance.alt.value);
});

test('an error event queued by an old media element cannot clear the newly selected file', async t => {
  const f = await preview(); t.after(f.dispose);
  const oldElement = {}, newElement = {};
  f.instance.previewElement.value = oldElement;
  const next = { ...file, id: 'video-2', url: file.url.replace('video-1', 'video-2') };
  f.props.media = next;
  await f.flush();
  f.instance.previewElement.value = newElement;
  f.instance.onError({ target: oldElement });
  assert.equal(f.instance.src.value, next.url);
  assert.equal(Boolean(f.instance.error.value), false);
  f.instance.onError({ target: f.instance.previewElement.value });
  assert.equal(f.instance.src.value, '');
  assert.ok(f.instance.error.value, 'an error from the current element must still be reported');
});

test('blob resolution cannot restore a previous file after switching media or losing permission', async t => {
  const local = { id: 'photo-1', kind: 'photo', blobId: 'blob-1', title: '本地照片' };
  const f = await preview(local); t.after(f.dispose);
  assert.equal(f.requests[0].id, 'blob-1');
  f.props.media = { ...local, id: 'photo-2', blobId: 'blob-2' };
  await f.flush();
  assert.equal(f.instance.src.value, '', 'the old picture must clear while a different file is loading');
  f.requests[0].resolve(new Blob(['stale']));
  await f.flush();
  assert.equal(f.created.length, 0, 'a late old blob must not allocate or display an object URL');
  f.requests[1].resolve(new Blob(['current']));
  await f.flush();
  assert.equal(f.instance.src.value, f.created[0].url);
  f.props.media = { ...local, id: 'photo-3', blobId: 'blob-3' };
  await f.flush();
  assert.deepEqual(f.revoked, [f.created[0].url], 'switching releases the old loaded blob');
  f.props.media = null;
  await f.flush();
  f.requests[2].resolve(new Blob(['revoked']));
  await f.flush();
  assert.equal(f.instance.src.value, '');
  assert.equal(f.created.length, 1, 'revoked media cannot return after a delayed read completes');
});

test('metadata refresh reuses a loaded blob and unmount releases it once', async () => {
  const local = { id: 'photo-1', kind: 'photo', blobId: 'blob-1', title: '本地照片' };
  const f = await preview(local);
  try {
    f.requests[0].resolve(new Blob(['image']));
    await f.flush();
    const loaded = f.instance.src.value;
    f.props.media = { ...local, title: '更新名称', version: 2 };
    await f.flush();
    assert.equal(f.instance.src.value, loaded);
    assert.equal(f.requests.length, 1);
    assert.deepEqual(f.revoked, []);
  } finally { f.dispose(); }
  assert.deepEqual(f.revoked, [f.created[0].url]);
});

test('a blob read completing after unmount cannot allocate a leaked object URL', async () => {
  const f = await preview({ id: 'photo-1', kind: 'photo', blobId: 'blob-1' });
  f.dispose();
  f.requests[0].resolve(new Blob(['late']));
  await f.flush();
  assert.deepEqual(f.created, []);
  assert.equal(f.instance.src.value, '');
});
