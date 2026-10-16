// UI regression: reads the local backend; intercepts every business write.
// ADMIN_TEST_PASSWORD and PLAYWRIGHT_MODULE are supplied by the runner.
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const output = path.resolve(__dirname, '../output/admin-form-feedback');
fs.mkdirSync(output, { recursive: true });
const steps = [], nativeDialogs = [], errors = [];
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
async function check(test, message) {
  for (let i = 0; i < 60; i++) { if (await test()) return; await sleep(100); }
  throw Error(message);
}
async function compactError(page, controlSelector, errorSelector) {
  const control = page.locator(controlSelector), message = page.locator(errorSelector);
  const inputBox = await control.boundingBox(), errorBox = await message.boundingBox();
  const gap = errorBox.y - inputBox.y - inputBox.height;
  assert(gap >= -0.5 && gap <= 4.5, `${errorSelector} must stay within 4px of its control (${gap}px)`);
}
(async () => {
  assert(process.env.ADMIN_TEST_PASSWORD, 'Provide ADMIN_TEST_PASSWORD');
  const browser = await chromium.launch({ headless: true, channel: 'msedge' });
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  page.on('dialog', async dialog => { nativeDialogs.push(dialog.type()); await dialog.dismiss(); });
  page.on('pageerror', error => errors.push(error.message));
  let mode = 'fields', writes = 0;
  await page.route('**/api/admin/v1/execute', async route => {
    writes++;
    await route.fulfill({ status: mode === 'fields' ? 400 : 503, contentType: 'application/json', body: JSON.stringify(mode === 'fields'
      ? { message: '校验失败', errorCode: 'VALIDATION_ERROR', fields: { code: '该编号已存在，请使用其他编号' } }
      : { message: '服务暂不可用，修改未保存' }) });
  });
  const editor = page.locator('dialog[open]').filter({ has: page.locator('#field-code') });
  const confirm = page.locator('dialog[open][aria-labelledby="discard-confirmation-heading"]');
  async function navigate(target) {
    // Use the mounted router: importing its URL again after Vite HMR creates
    // a second instance that changes the hash without updating the mounted view.
    await page.evaluate(target => { window.feedbackNavigation = document.querySelector('#app').__vue_app__.config.globalProperties.$router.push(target); }, target);
  }
  try {
    await page.goto('http://127.0.0.1:5181/#/admin/people');
    await page.locator('#admin-username').fill(process.env.ADMIN_TEST_ACCOUNT || 'admin');
    await page.locator('#admin-password').fill(process.env.ADMIN_TEST_PASSWORD);
    await page.getByRole('button', { name: '登录', exact: true }).click();
    await page.getByRole('button', { name: '新增人员', exact: true }).click();
    await editor.getByRole('button', { name: '保存本地记录' }).click();
    await check(async () => (await page.locator('#error-code').textContent()).includes('请填写编号'), 'Missing inline code error');
    assert((await page.locator('#error-name').textContent()).includes('请填写名称'));
    await compactError(page, '#field-code', '#error-code');
    await compactError(page, '#field-name', '#error-name');
    assert.equal(await editor.locator('.notice.error').count(), 0);
    assert.equal(await page.evaluate(() => document.activeElement.id), 'field-code');
    assert.equal(writes, 0);
    await page.screenshot({ path: path.join(output, 'person-validation.png') });
    steps.push('empty person form: inline errors, first invalid field focused, no write');
    await page.locator('#field-code').fill('QA-DRAFT-NOT-SAVED');
    assert.equal(await page.locator('#error-code').textContent(), '');
    assert((await page.locator('#error-name').textContent()).includes('请填写名称'));
    await page.locator('#field-name').fill('表单交互验证（不保存）');
    await editor.getByRole('button', { name: '保存本地记录' }).click();
    await check(async () => (await page.locator('#error-code').textContent()).includes('该编号已存在'), 'Server field feedback missing');
    assert.equal(await editor.locator('[data-form-error]').count(), 0);
    await page.locator('#field-code').fill('QA-DRAFT-EDITED');
    assert.equal(await page.locator('#error-code').textContent(), '');
    mode = 'network';
    await editor.getByRole('button', { name: '保存本地记录' }).click();
    await check(async () => (await editor.locator('[data-form-error]').textContent()).includes('服务暂不可用'), 'Generic failure missing');
    assert.equal(await page.locator('#field-code').inputValue(), 'QA-DRAFT-EDITED');
    steps.push('server field error and unavailable service retain draft and display feedback');
    await editor.getByRole('button', { name: '取消', exact: true }).click();
    await confirm.waitFor();
    await page.screenshot({ path: path.join(output, 'discard-confirmation.png') });
    await confirm.getByRole('button', { name: '继续编辑' }).click();
    assert.equal(await page.locator('#field-code').inputValue(), 'QA-DRAFT-EDITED');
    await editor.getByRole('button', { name: '取消', exact: true }).click();
    await confirm.waitFor(); await page.keyboard.press('Escape');
    await check(async () => await confirm.count() === 0, 'Escape did not cancel confirmation');
    assert.equal(await editor.count(), 1);
    await navigate('/admin/assets/devices');
    await confirm.waitFor();
    await confirm.getByRole('button', { name: '继续编辑' }).click();
    await page.evaluate(() => window.feedbackNavigation);
    assert(page.url().includes('/admin/people'));
    await navigate('/admin/assets/devices');
    await confirm.waitFor();
    await confirm.getByRole('button', { name: '放弃修改' }).click();
    await page.evaluate(() => window.feedbackNavigation);
    await check(async () => page.url().includes('/admin/assets/devices'), 'Accepted navigation blocked');
    steps.push('custom close/navigation confirmation; cancellation and Escape preserve draft');
    await page.getByRole('button', { name: '新建设备', exact: true }).click();
    const device = page.locator('dialog[open]').filter({ has: page.locator('#device-code') });
    await device.getByRole('button', { name: '保存设备档案' }).click();
    assert((await device.locator('#error-code').textContent()).includes('请填写'));
    assert((await device.locator('#error-name').textContent()).includes('请填写'));
    await compactError(page, '#device-code', '#error-code');
    await compactError(page, '#device-name', '#error-name');
    assert.equal(await device.locator('.notice.error').count(), 0);
    await device.locator('#device-code').fill('QA-DEVICE-DRAFT');
    await device.getByRole('button', { name: '取消', exact: true }).click();
    await confirm.getByRole('button', { name: '放弃修改' }).click();
    steps.push('device validation and custom discard confirmation');
    await navigate('/admin/access/accounts');
    await page.getByRole('button', { name: '查看', exact: true }).nth(1).click();
    await page.getByRole('button', { name: '重置登录密码', exact: true }).click();
    const reset = page.locator('dialog[open][aria-labelledby="reset-credential-heading"]');
    await reset.getByRole('button', { name: '确认重置登录密码' }).click();
    await check(async () => await reset.locator('#reset-error-password').count() === 1, 'Password validation missing');
    assert.equal(await reset.locator('#reset-error-reason').count(), 1);
    assert.equal(await reset.locator('#reset-error-confirm').count(), 1);
    await compactError(page, '#reset-password', '#reset-error-password');
    await compactError(page, '#reset-reason', '#reset-error-reason');
    await compactError(page, 'label:has(#reset-confirm)', '#reset-error-confirm');
    await page.screenshot({ path: path.join(output, 'reset-validation.png') });
    assert.equal(await page.evaluate(() => document.activeElement.id), 'reset-password');
    assert.equal(writes, 2);
    await reset.getByRole('button', { name: '关闭面板' }).click();
    steps.push('reset password validation inline; no credentials changed');
    await navigate('/admin/assets/assignments');
    await page.evaluate(() => window.feedbackNavigation);
    await page.getByRole('button', { name: '办理领用', exact: true }).first().click();
    const assignment = page.locator('dialog[open][aria-labelledby="assignment-heading"]');
    await assignment.getByRole('textbox', { name: '人员关键词' }).fill('办理草稿');
    await assignment.getByRole('button', { name: '取消', exact: true }).click();
    await confirm.getByRole('button', { name: '继续编辑' }).click();
    assert.equal(await assignment.getByRole('textbox', { name: '人员关键词' }).inputValue(), '办理草稿');
    await assignment.getByRole('button', { name: '取消', exact: true }).click();
    await confirm.getByRole('button', { name: '放弃修改' }).click();
    steps.push('assignment discard cancellation preserves selection form; no asset writes');
    await navigate('/admin/people');
    await page.getByRole('button', { name: '新增人员', exact: true }).click();
    await page.locator('#field-name').fill('窄屏交互验证');
    await page.setViewportSize({ width: 390, height: 844 });
    await editor.getByRole('button', { name: '取消', exact: true }).click();
    await confirm.waitFor();
    const bounds = await confirm.boundingBox();
    assert(bounds.x >= 0 && bounds.x + bounds.width <= 391);
    await page.screenshot({ path: path.join(output, 'discard-narrow.png') });
    await confirm.getByRole('button', { name: '放弃修改' }).click();
    await page.setViewportSize({ width: 1440, height: 1000 });
    await page.getByRole('button', { name: /^账号：/ }).click();
    await page.getByRole('button', { name: '退出登录' }).click();
    await page.locator('#admin-username').waitFor();
    assert.deepEqual(nativeDialogs, []);
    assert.deepEqual(errors, []);
    steps.push('narrow viewport fits; no native dialogs or page errors; test session logged out');
    console.log(JSON.stringify({ passed: steps.length, steps, interceptedWrites: writes, nativeDialogs }, null, 2));
  } catch (error) {
    await page.screenshot({ path: path.join(output, 'failure.png') });
    fs.writeFileSync(path.join(output, 'failure.txt'), await page.locator('body').innerText());
    console.error({ url: page.url(), steps, errors, nativeDialogs });
    throw error;
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
