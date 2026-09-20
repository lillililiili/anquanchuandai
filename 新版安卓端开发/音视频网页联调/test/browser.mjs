import { createRequire } from 'node:module';
import { mkdir, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const base = process.env.CALL_LAB_URL || 'http://localhost:5188';
const browser = await chromium.launch({
  channel: 'chrome', headless: true,
  args: ['--autoplay-policy=no-user-gesture-required'],
});
const errors = [], results = [];
const artifacts = new URL('../artifacts/', import.meta.url);
await mkdir(artifacts, { recursive: true });
async function makePage(account, viewport = { width: 1440, height: 1100 }) {
  const context = await browser.newContext({ viewport });
  await context.addInitScript(() => {
    window.deviceRequests = 0;
    if (navigator.mediaDevices) navigator.mediaDevices.getUserMedia = async () => { window.deviceRequests++; throw new Error('Real device capture is forbidden in this test'); };
  });
  const page = await context.newPage();
  page.on('pageerror', error => errors.push(error.message));
  await page.goto(`${base}/?account=${account}&transport=webrtc`);
  await page.waitForFunction(() => document.getElementById('identityStatus').textContent === '已上线');
  return page;
}
async function waitState(page, state) { await page.waitForFunction(value => document.getElementById('callState').dataset.state === value, state, { timeout: 20000 }); }
try {
  const a = await makePage('dispatch'), b = await makePage('helmet-001');
  await a.locator('[data-account="helmet-001"]').click();
  await a.screenshot({ path: fileURLToPath(new URL('desktop-idle.png', artifacts)), fullPage: true });
  await a.locator('#videoCall').click();
  await waitState(b, 'ringing');
  await b.locator('#accept').click();
  await Promise.all([waitState(a, 'connected'), waitState(b, 'connected')]);
  await Promise.all([a, b].map(page => page.waitForFunction(() => parseFloat(document.getElementById('receivedBytes').textContent) > 1 && document.getElementById('remoteVideo').videoWidth === 640)));
  results.push('video: both peers connected, receive bytes > 1 KB, decoded video width 640');
  const stats = await Promise.all([a, b].map(page => page.evaluate(() => ({ sent: document.getElementById('sentBytes').textContent, received: document.getElementById('receivedBytes').textContent, width: document.getElementById('remoteVideo').videoWidth, deviceRequests: window.deviceRequests }))));
  await a.screenshot({ path: fileURLToPath(new URL('desktop-connected.png', artifacts)), fullPage: true });
  await a.locator('#mute').click(); assert.match(await a.locator('#mute').innerText(), /恢复/);
  await a.locator('#camera').click(); assert.match(await a.locator('#camera').innerText(), /恢复/);
  await a.evaluate(() => { window.oldTracks = document.getElementById('localVideo').srcObject.getTracks(); });
  await a.locator('#hangup').click();
  await Promise.all([waitState(a, 'ended'), waitState(b, 'ended')]);
  assert.equal(await a.evaluate(() => window.oldTracks.every(t => t.readyState === 'ended')), true);
  results.push('mute/video pause and hangup: source tracks released, both peers ended');
  await b.locator('[data-account="dispatch"]').click();
  await b.locator('#audioCall').click(); await waitState(a, 'ringing');
  await a.locator('#reject').click(); await waitState(b, 'ended');
  assert.match(await b.locator('#history').innerText(), /被拒接/);
  results.push('reverse call and reject: both peers return to idle controls');
  await b.locator('#audioCall').click(); await waitState(a, 'ringing'); await a.locator('#accept').click();
  await Promise.all([waitState(a, 'connected'), waitState(b, 'connected')]);
  await a.waitForFunction(() => parseFloat(document.getElementById('receivedBytes').textContent) > 1);
  assert.equal(await a.locator('#camera').isVisible(), false);
  results.push('audio only: bidirectional encoded audio flows without camera');
  await b.close(); await waitState(a, 'ended');
  results.push('peer browser close: remaining peer terminates');
  await a.locator('#account').selectOption('inspector'); await a.locator('#login').click();
  await a.waitForFunction(() => document.getElementById('myName').textContent === '巡检员');
  results.push('account switch: identity changes after hangup');
  const mobile = await makePage('helmet-002', { width: 390, height: 844 });
  assert.equal(await mobile.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
  await mobile.screenshot({ path: fileURLToPath(new URL('mobile.png', artifacts)), fullPage: true });
  await mobile.locator('#transport').selectOption('agora');
  assert.equal(await mobile.locator('#videoCall').isDisabled(), true);
  assert.match(await mobile.locator('#modeHint').innerText(), /未就绪/);
  results.push('mobile 390px: no overflow; missing Agora configuration disables calls');
  assert.equal(await a.evaluate(() => window.deviceRequests), 0);
  assert.equal(await mobile.evaluate(() => window.deviceRequests), 0);
  await a.addScriptTag({ url: `${base}/agora-sdk.js` });
  const agoraTracks = await a.evaluate(async () => {
    const { createSource } = await import('/source.js');
    const sdk = window.AgoraRTC; sdk.setLogLevel(4); sdk.disableLogUpload();
    const source = await createSource({ video: true, name: 'SDK 验证', sn: 'TEST' });
    const audio = sdk.createCustomAudioTrack({ mediaStreamTrack: source.stream.getAudioTracks()[0] });
    const video = sdk.createCustomVideoTrack({ mediaStreamTrack: source.stream.getVideoTracks()[0], width: 640, height: 360, frameRate: 15, bitrateMin: 150, bitrateMax: 700 });
    const kinds = [audio.getMediaStreamTrack().kind, video.getMediaStreamTrack().kind];
    audio.close(); video.close(); source.stop();
    return kinds;
  });
  assert.deepEqual(agoraTracks, ['audio', 'video']);
  assert.equal(await a.evaluate(() => window.deviceRequests), 0);
  results.push('Agora SDK: custom synthetic audio/video tracks created and released; cloud join not tested');
  assert.deepEqual(errors, []);
  await writeFile(new URL('browser-results.json', artifacts), JSON.stringify({ at: new Date().toISOString(), results, stats, pageErrors: errors, agoraLiveTested: false }, null, 2));
  console.log(JSON.stringify({ results, stats, pageErrors: errors, agoraLiveTested: false }, null, 2));
} catch (error) {
  for (const context of browser.contexts()) for (const page of context.pages()) {
    console.error('PAGE', page.url(), (await page.locator('body').innerText()).slice(0, 3500));
  }
  throw error;
} finally { await browser.close(); }
