// Real local pages with all business writes intercepted. No device commands run.
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const output = path.resolve(__dirname, '../output/pc-inline-validation');
fs.mkdirSync(output, { recursive: true });
const steps = [], pageErrors = [], writes = [], dialogs = [], spacing = [];
async function wait(test, message) {
  for (let i = 0; i < 60; i++) { if (await test()) return; await new Promise(r => setTimeout(r, 100)); }
  throw Error(message);
}
async function fieldError(page, selector, text) {
  const field = page.locator(selector);
  await wait(async () => (await field.innerText()).includes(text), 'Missing inline error: ' + text);
  const message = field.locator('.field-error, .ui-control-error, small.error').last();
  assert(await message.isVisible());
  const style = await message.evaluate(el => ({ color: getComputedStyle(el).color, size: getComputedStyle(el).fontSize }));
  assert.equal(style.size, '12px');
  const [red, green] = style.color.match(/\d+/g).map(Number);
  assert(red > green, 'Error text must be red');
  const gap = await message.evaluate(el => {
    const feedback = el.closest('.field-feedback') || el;
    const previous = el.classList.contains('ui-control-error')
      ? el.parentElement.querySelector('.ui-date-input, .ui-select-trigger')
      : feedback.previousElementSibling;
    return el.getBoundingClientRect().top - previous.getBoundingClientRect().bottom;
  });
  assert(gap >= -0.5 && gap <= 4.5, `Feedback gap must be 0–4px: ${selector} (${gap}px)`);
  spacing.push({ selector, gap });
  const control = field.locator('input:not(.ui-native-proxy), textarea, [role="combobox"]').first();
  if (await control.count()) {
    const inputBox = await control.boundingBox(), errorBox = await message.boundingBox();
    assert(errorBox.y >= inputBox.y + inputBox.height - 1, 'Error must be below the control: ' + selector);
  }
}
(async () => {
  assert(process.env.ADMIN_TEST_PASSWORD, 'Provide ADMIN_TEST_PASSWORD');
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  await context.addInitScript(() => {
    window.nativeValidation = [];
    document.addEventListener('invalid', event => { setTimeout(() => window.nativeValidation.push({ prevented: event.defaultPrevented, name: event.target.name || event.target.id }), 0); }, true);
  });
  await context.route('**/api/**', async route => {
    const request = route.request(), url = new URL(request.url());
    const isRead = request.method() === 'GET' || /\/(query|login|logout)$/.test(url.pathname);
    if (isRead) return route.continue();
    writes.push(url.pathname);
    return route.fulfill({ status: 503, contentType: 'application/json', body: JSON.stringify({ message: '验证拦截：未写入业务数据' }) });
  });
  let page;
  try {
    for (const [port, prefix, accountName] of [[5191, 'portal', 'account'], [5181, 'admin', 'username']]) {
      page = await context.newPage();
      page.on('pageerror', e => pageErrors.push(e.message));
      page.on('dialog', async d => { dialogs.push(d.type()); await d.dismiss(); });
      let loginRequests = 0;
      page.on('request', req => { if (/\/login$/.test(req.url()) && req.method() === 'POST') loginRequests++; });
      await page.goto(`http://127.0.0.1:${port}/#/${prefix === 'admin' ? 'admin/' : ''}login`);
      await page.getByRole('button', { name: '登录', exact: true }).click();
      await fieldError(page, prefix === 'admin' ? '.login-field:has([name="username"])' : '.field:has([name="account"])', prefix === 'admin' ? '请输入管理账号' : '请输入工作账号');
      await fieldError(page, prefix === 'admin' ? '.login-field:has([name="password"])' : '.field:has([name="password"])', '请输入密码');
      assert.equal(await page.locator('form').evaluate(el => el.noValidate), true);
      assert.equal(loginRequests, 0);
      await page.screenshot({ path: path.join(output, `${prefix}-login-validation.png`) });
      await page.locator(`[name="${accountName}"]`).fill('   ');
      await page.locator('[name="password"]').press('Enter');
      assert.equal(loginRequests, 0);
      await page.locator(`[name="${accountName}"]`).fill(process.env.ADMIN_TEST_ACCOUNT || 'admin');
      assert.equal(await page.locator(`#${prefix === 'admin' ? 'admin-username' : 'portal-account'}-error`).count(), 0);
      await page.locator('[name="password"]').fill(process.env.ADMIN_TEST_PASSWORD);
      await page.getByRole('button', { name: '登录', exact: true }).click();
      await wait(async () => !page.url().includes('login'), 'Valid login did not complete');
      steps.push(`${prefix}: empty/space/Enter validation inline, no request until valid login`);
      if (prefix === 'admin') {
        await page.evaluate(() => document.querySelector('#app').__vue_app__.config.globalProperties.$router.push('/admin/people'));
        await page.getByRole('button', { name: '新增人员', exact: true }).click();
        const modal = page.locator('dialog[open]').filter({ has: page.locator('#field-code') });
        await modal.getByRole('button', { name: '保存本地记录' }).click();
        assert((await page.locator('#error-code').textContent()).includes('请填写编号'));
        assert((await page.locator('#error-name').textContent()).includes('请填写名称'));
        await fieldError(page, 'label:has(#field-code)', '请填写编号');
        await fieldError(page, 'label:has(#field-name)', '请填写名称');
        await modal.getByRole('button', { name: '取消', exact: true }).click();
        await page.evaluate(() => document.querySelector('#app').__vue_app__.config.globalProperties.$router.push('/admin/audit'));
        const dates = page.locator('.ui-date-input');
        await dates.nth(0).fill('2026-10-15'); await dates.nth(0).press('Tab');
        await dates.nth(1).fill('2026-10-14'); await dates.nth(1).press('Tab');
        await page.getByRole('button', { name: '查询', exact: true }).click();
        await fieldError(page, '[data-field="dateTo"]', '结束日期不能早于开始日期');
        await page.getByRole('button', { name: /^账号：/ }).click();
        await page.getByRole('button', { name: '退出登录' }).click();
        steps.push('admin person and audit date-range validation inline');
      }
    }
    // Reuse the authenticated portal page from the first loop iteration.
    page = context.pages()[0];
    async function go(target) { await page.evaluate(target => document.querySelector('#app').__vue_app__.config.globalProperties.$router.push(target), target); }
    await go('/dispatch');
    await page.getByRole('button', { name: '新建分组' }).click();
    const group = page.locator('form[data-form="group"]');
    await group.getByRole('button', { name: '保存分组' }).click();
    await fieldError(page, 'form[data-form="group"] [data-field="name"]', '请填写分组名称');
    await fieldError(page, 'form[data-form="group"] [data-field="members"]', '请选择成员');
    await page.screenshot({ path: path.join(output, 'group-validation.png') });
    await group.locator('[name="name"]').fill('表单校验测试');
    assert.equal(await group.locator('[data-field="name"] .field-error').count(), 0);
    await group.getByRole('button', { name: '取消', exact: true }).click();
    const broadcast = page.locator('form[data-form="broadcast"]');
    await broadcast.locator('textarea').fill('  ');
    await broadcast.getByRole('button', { name: '发送广播' }).click();
    await fieldError(page, '[data-form="broadcast"] [data-field="text"]', '请输入广播内容');
    await broadcast.getByRole('button', { name: '试听', exact: true }).click();
    assert.equal(await page.getByRole('alert').filter({ hasText: '请输入广播内容' }).count(), 0);
    steps.push('group name/member and broadcast text validation inline; no device request');
    await go('/fences');
    await page.getByRole('button', { name: '新建围栏', exact: true }).click();
    await page.getByRole('button', { name: '保存围栏' }).click();
    await fieldError(page, '[data-field="name"]', '请填写围栏名称');
    await fieldError(page, '[data-field="points"]', '请在地图上绘制至少3个节点');
    await page.screenshot({ path: path.join(output, 'fence-validation.png') });
    steps.push('fence name and map range validation inline');
    await go('/tracks');
    await page.locator('input[name="start"]').fill('12:00');
    await page.locator('input[name="end"]').fill('11:00');
    await page.getByRole('button', { name: '查询轨迹' }).click();
    await fieldError(page, '[data-field="end"]', '结束时间必须晚于开始时间');
    await page.locator('input[name="end"]').fill('13:00');
    assert.equal(await page.locator('[data-field="end"] .field-error').count(), 0);
    const date = page.locator('.ui-date-input').first();
    await date.fill('2026-99-40'); await date.press('Tab');
    await page.getByRole('button', { name: '查询轨迹' }).click();
    await fieldError(page, '.ui-date', '请输入有效日期');
    await date.fill('2026-10-15'); await date.press('Tab');
    await wait(async () => await page.locator('.ui-date .ui-control-error').count() === 0, 'Correct date must clear error');
    steps.push('track time range and malformed date inline; correction clears error');
    await go('/alarms');
    const link = page.locator('a[href^="#/event/"]').first();
    await link.waitFor();
    // Choose an event with an enabled verification form, without changing it.
    const ids = await page.locator('a[href^="#/event/"]').evaluateAll(links => [...new Set(links.map(a => a.getAttribute('href').slice(1)))]);
    let verified = false;
    for (const target of ids) {
      await go(target);
      const submit = page.getByRole('button', { name: '提交核验记录' });
      if (!await submit.count()) continue;
      await page.locator('textarea[name="situation"]').fill('');
      await submit.click();
      await fieldError(page, '[data-field="situation"]', '请填写现场情况');
      if (await page.locator('[data-field="conclusion"] .field-error').count()) {
        await fieldError(page, '[data-field="conclusion"]', '请选择核验结论');
      }
      const situation = page.locator('[data-field="situation"]');
      const errorBox = await situation.locator('.field-error').boundingBox();
      const countBox = await situation.locator('.field-hint').boundingBox();
      assert(Math.abs(errorBox.y - countBox.y) <= 1, 'Character count must share the feedback row');
      await page.locator('input[type="file"]').setInputFiles({ name: 'invalid.txt', mimeType: 'text/plain', buffer: Buffer.from('validation only') });
      await fieldError(page, '.field:has(input[type="file"])', '仅支持 JPG、PNG');
      await page.screenshot({ path: path.join(output, 'event-validation.png') });
      await page.setViewportSize({ width: 860, height: 1000 });
      await fieldError(page, '[data-field="situation"]', '请填写现场情况');
      const narrowError = await situation.locator('.field-error').boundingBox();
      const narrowHint = await situation.locator('.field-hint').boundingBox();
      assert(narrowError.x + narrowError.width <= narrowHint.x, 'Feedback and character count must not overlap');
      await page.screenshot({ path: path.join(output, 'event-validation-narrow.png') });
      await page.setViewportSize({ width: 1440, height: 1000 });
      verified = true; break;
    }
    assert(verified, 'No editable event available for verification test');
    steps.push('event verification required fields and photo type errors inline');
    for (const p of context.pages()) assert((await p.evaluate(() => window.nativeValidation)).every(item => item.prevented), 'Native validation bubble not prevented');
    assert.deepEqual(writes, [], 'Invalid forms must not submit any business writes');
    assert.deepEqual(dialogs, []);
    assert.deepEqual(pageErrors, []);
    console.log(JSON.stringify({ passed: steps.length, steps, spacing, businessWrites: writes.length }, null, 2));
  } catch (error) {
    if (page) { await page.screenshot({ path: path.join(output, 'failure.png') }); fs.writeFileSync(path.join(output, 'failure.txt'), await page.locator('body').innerText()); }
    console.error({ steps, pageErrors, writes }); throw error;
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
