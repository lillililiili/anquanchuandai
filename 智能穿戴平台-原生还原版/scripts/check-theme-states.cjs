/* Component-state and geometry checks in an ephemeral browser context. */
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {spawn} = require('node:child_process');
const root = path.resolve(__dirname, '..');
const qaRoot = path.resolve(root, process.env.THEME_QA_DIR || 'qa/theme');
const output = path.join(qaRoot, 'states');
const base = 'http://127.0.0.1:5210';
const runtime = process.env.PLAYWRIGHT_MODULE || 'C:/Users/19221/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright';
const {chromium} = require(runtime);
const sizes = [[1672, 941], [1366, 768], [1920, 1080]];
const results = [], browserErrors = [], failedRequests = [];
const save = () => fs.writeFileSync(path.join(output, 'results.json'), JSON.stringify({results, browserErrors, failedRequests}, null, 2));
const capture = (page, name) => page.screenshot({path: path.join(output, name + '.png'), fullPage: true, animations: 'disabled'});
async function section(page, name, fn) {
  const checks = [], measurements = [];
  const check = (condition, description, measurement) => {
    if (measurement !== undefined) measurements.push({description, value: measurement});
    assert(condition, description + (measurement !== undefined ? ': ' + JSON.stringify(measurement) : ''));
    checks.push(description);
  };
  try {
    await fn(check);
    results.push({name, passed: true, checks, measurements});
    fs.rmSync(path.join(output, 'failure-' + name + '.png'), {force: true});
    console.log('PASS', name, checks.length + ' checks');
  } catch (error) {
    await capture(page, 'failure-' + name).catch(() => {});
    results.push({name, passed: false, checks, measurements, error: error.stack});
    console.error('FAIL', name, error.message);
  } finally {save();}
}
async function colors(locator) {
  return locator.evaluate(el => {
    const style = getComputedStyle(el);
    // Keep opacity alongside RGB: a swatch at 20% is different from its solid hex.
    const rgba = value => {
      const match = value.match(/^rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)$/);
      return match ? {hex: '#' + match.slice(1, 4).map(n => (+n).toString(16).padStart(2, '0')).join(''), alpha: match[4] === undefined ? 1 : +match[4], css: value} : {hex: value, alpha: null, css: value};
    };
    const background = rgba(style.backgroundColor), color = rgba(style.color), border = rgba(style.borderTopColor), outline = rgba(style.outlineColor);
    return {background: background.hex, backgroundAlpha: background.alpha, backgroundCss: background.css, backgroundImage: style.backgroundImage, color: color.hex, colorAlpha: color.alpha, border: border.hex, borderAlpha: border.alpha, borderWidth: style.borderTopWidth, borderRadius: style.borderTopLeftRadius, outline: outline.hex, outlineAlpha: outline.alpha, outlineWidth: style.outlineWidth, outlineStyle: style.outlineStyle, focusVisible: el.matches(':focus-visible'), width: el.getBoundingClientRect().width, height: el.getBoundingClientRect().height};
  });
}
const alphaNear = (actual, expected) => Math.abs(actual - expected) < 0.005;
async function go(page, name) {
  await page.goto(base + '/#/' + name);
  await page.waitForFunction(() => window.R && document.querySelector('.main, .login-card, .screen'));
  await page.evaluate(async () => {await document.fonts.ready; await Promise.all([...document.images].map(img => img.decode().catch(() => {})));});
}
async function settle(page) {await page.waitForTimeout(220);}
async function login(page) {
  await go(page, 'login');
  await page.locator('[name="account"]').fill('admin');
  await page.locator('[name="password"]').fill('123456');
  await page.locator('[name="captcha"]').fill(await page.locator('.captcha-code').innerText());
  await page.getByRole('button', {name: '登录', exact: true}).click();
  await page.waitForURL(base + '/#/overview');
}
(async () => {
  fs.mkdirSync(output, {recursive: true});
  const server = spawn(process.execPath, [path.join(root, 'server.js'), '--port', '5210'], {windowsHide: true, stdio: ['ignore', 'pipe', 'pipe']});
  let browser;
  try {
    await new Promise((resolve, reject) => {
      server.stdout.once('data', resolve);
      server.once('error', reject);
      server.once('exit', code => reject(Error('Preview server exited: ' + code)));
    });
    browser = await chromium.launch({headless: true, executablePath: process.env.CHROME_PATH || 'C:/Program Files/Google/Chrome/Application/chrome.exe'});
    const context = await browser.newContext({viewport: {width: 1672, height: 941}, deviceScaleFactor: 1});
    const page = await context.newPage();
    page.setDefaultTimeout(12000);
    page.on('pageerror', error => browserErrors.push(error.message));
    page.on('response', response => {if (response.status() >= 400) failedRequests.push(response.url());});
    await section(page, 'button-input-states', async check => {
      await go(page, 'login');
      const button = page.locator('.login-card button[type="submit"]');
      await page.mouse.move(5, 5); await settle(page);
      let value = await colors(button);
      check(value.background === '#4faff7', '主按钮默认色为 #4FAFF7', value);
      check(value.height === 40, '登录主按钮高40px', value.height);
      const inputs = await page.locator('.login-card input').evaluateAll(nodes => nodes.map(el => ({name: el.name, height: el.getBoundingClientRect().height})));
      check(inputs.every(x => x.height === 32), '登录输入框均为32px', inputs);
      await button.hover(); await settle(page);
      value = await colors(button);
      check(value.background === '#7fcefa', '主按钮悬停色为 #7FCEFA', value);
      await page.mouse.down(); await settle(page);
      value = await colors(button);
      check(value.background === '#3c89f5', '主按钮按下色为 #3C89F5', value);
      await page.mouse.up();
      await page.mouse.move(5, 5);
      // Exercise the existing :disabled style without changing app state or source.
      await button.evaluate(el => {el.disabled = true;}); await settle(page);
      value = await colors(button);
      check(value.background === '#193a60' && value.color === '#677987', '禁用主按钮底色与文字符合规范', value);
      await button.evaluate(el => {el.disabled = false;});
      await button.focus();
      await page.keyboard.press('Shift+Tab'); await page.keyboard.press('Tab'); await settle(page);
      value = await colors(button);
      check(value.focusVisible && value.outline === '#83f6fd' && value.outlineWidth === '2px' && value.outlineStyle === 'solid', '键盘焦点显示2px青色外框', value);
      await capture(page, 'login-button-focus');
      const input = page.locator('[name="account"]');
      await button.evaluate(el => el.blur());
      await page.mouse.move(5, 5); await settle(page);
      value = await colors(input);
      check(value.height === 32 && value.borderRadius === '4px' && value.backgroundAlpha === 0 && value.border === '#83f6fd' && alphaNear(value.borderAlpha, 0.35) && value.borderWidth === '1px', '输入框32px高、4px圆角、透明底及35%青色1px边框', value);
      await input.hover(); await settle(page);
      value = await colors(input);
      check(value.border === '#83f6fd' && value.borderAlpha === 1 && value.borderWidth === '1px', '输入框悬停使用不透明青色1px边框', value);
      await input.focus(); await settle(page);
      value = await colors(input);
      check(value.border === '#83f6fd' && value.borderAlpha === 1 && value.borderWidth === '2px' && value.height === 32, '输入框聚焦青色2px边框且高度仍为32px', value);
      await capture(page, 'login-input-focus');
      await input.evaluate(el => {el.disabled = true;});
      await page.mouse.move(5, 5); await settle(page);
      value = await colors(input);
      check(value.background === '#7fcefa' && alphaNear(value.backgroundAlpha, 0.2) && value.border === '#83f6fd' && alphaNear(value.borderAlpha, 0.2) && value.color === '#677987', '禁用输入框保留20%底色/边框及禁用文字', value);
      await input.evaluate(el => {el.disabled = false;});


    });
    await login(page);
    await section(page, 'table-form-modal', async check => {
      await go(page, 'personnel');
      await page.mouse.move(5, 5);
      const rows = page.locator('.personnel-list tbody tr');
      const selected = await colors(rows.filter({has: page.locator('[href="#/person/P1"]')}));
      check(selected.background === '#254570', '人员选中行背景为 #254570', selected);
      const even = await colors(rows.nth(1)), odd = await colors(rows.nth(2));
      check(even.background === '#112345' && alphaNear(even.backgroundAlpha, 0.8) && odd.background === '#0d1d3a' && alphaNear(odd.backgroundAlpha, 0.9), '表格单双行保留源色值与80%/90%透明度', {even, odd});
      const head = await colors(page.locator('.personnel-list thead'));
      check(head.background === '#25556f' && head.backgroundAlpha === 1, '表头使用不透明#25556F', head);
      await rows.nth(1).hover(); await settle(page);
      const hovered = await colors(rows.nth(1));
      check(hovered.background === '#25556f' && alphaNear(hovered.backgroundAlpha, 0.2), '表格悬停映射原稿组件背景3的20%透明度', hovered);
      await page.mouse.move(5, 5);
      const panel = await colors(page.locator('.main .panel').first());
      check(panel.background === '#50b1f9' && alphaNear(panel.backgroundAlpha, 0.12) && panel.border === '#83f6fd' && alphaNear(panel.borderAlpha, 0.5), '普通面板使用12%卡片底与50%青色边框', panel);
      const option = await colors(page.locator('.filters select option').first());
      check(option.background === '#2e6086' && option.backgroundAlpha === 1, '下拉选项配置使用原稿#2E6086实底', option);

      const fields = await page.locator('.filters input, .filters select, .filters .btn').evaluateAll(nodes => nodes.map(el => ({text: el.name || el.textContent.trim(), height: el.getBoundingClientRect().height})));
      check(fields.every(x => x.height === 32), '普通筛选表单控件与按钮高32px', fields);
      await page.locator('[data-action="notifications"]').click();
      await page.locator('.modal').waitFor();
      const modal = await colors(page.locator('.modal'));
      check(modal.background === '#121e37' && modal.backgroundAlpha === 1 && modal.backgroundImage.includes('rgba(80, 177, 249, 0.12)') && modal.border === '#83f6fd' && alphaNear(modal.borderAlpha, 0.5) && modal.borderWidth === '1px', '弹窗以12%卡片色叠页面实底且边框青色50%/1px', modal);
      await capture(page, 'notification-modal');
      await page.locator('.modal [data-action="modal-close"]').last().click();
    });
    await section(page, 'link-danger-states', async check => {
      await go(page, 'personnel');
      const link = page.locator('.main .text-link').first();
      await page.mouse.move(5, 5); await settle(page);
      let value = await colors(link);
      check(value.color === '#83f6fd', '文字链接默认使用#83F6FD', value);
      await link.hover(); await settle(page);
      value = await colors(link);
      check(value.color === '#a0f8fd', '文字链接悬停使用#A0F8FD', value);
      await page.mouse.down(); await settle(page);
      value = await colors(link);
      check(value.color === '#5dcad2', '文字链接按下使用#5DCAD2', value);
      // Release away from the link: inspect :active without invoking navigation.
      await page.mouse.move(5, 5); await page.mouse.up();
      await link.evaluate(el => el.setAttribute('aria-disabled', 'true')); await settle(page);
      value = await colors(link);
      check(value.color === '#677987', '文字链接禁用使用实际组件禁用文字#677987', value);
      await link.evaluate(el => el.removeAttribute('aria-disabled'));
      await go(page, 'sos');
      const danger = page.locator('.btn.danger').first();
      await page.mouse.move(5, 5); await settle(page);
      value = await colors(danger);
      check(value.color === '#de554f' && value.border === '#de554f' && value.background === '#de554f' && alphaNear(value.backgroundAlpha, 0.25), '危险按钮默认红色边框/文字与25%红底', value);
      await danger.hover(); await settle(page);
      value = await colors(danger);
      check(value.background === '#e57163' && value.border === '#e57163', '危险按钮悬停使用#E57163', value);
      await page.mouse.down(); await settle(page);
      value = await colors(danger);
      check(value.background === '#a03e35' && value.border === '#a03e35', '危险按钮按下使用#A03E35', value);
      await page.mouse.move(5, 5); await page.mouse.up();
      await danger.evaluate(el => {el.disabled = true;}); await settle(page);
      value = await colors(danger);
      check(value.background === '#f4bcb2' && value.border === '#f4bcb2' && value.color === '#677987', '危险按钮禁用使用#F4BCB2与禁用文字', value);
      await capture(page, 'danger-disabled');
      await danger.evaluate(el => {el.disabled = false;});
    });
    for (const [width, height] of sizes) {
      await page.setViewportSize({width, height});
      await section(page, 'personnel-tabs-' + width, async check => {
        await go(page, 'personnel');
        for (const [index, tab] of ['装备信息', '作业信息', '事件信息'].entries()) {
          await page.locator(`[data-action="person-tab"][data-id="${tab}"]`).click();
          await page.locator(`aside[data-detail-tab="${tab}"]`).waitFor();
          const measurements = await page.locator('aside .btn').evaluateAll(nodes => nodes.map(el => {
            const r = el.getBoundingClientRect(), a = el.closest('aside').getBoundingClientRect();
            return {text: el.textContent.trim() || el.getAttribute('aria-label'), width: el.clientWidth, scrollWidth: el.scrollWidth, left: r.left, right: r.right, top: r.top, bottom: r.bottom, card: {left:a.left, right:a.right, top:a.top, bottom:a.bottom}, fits: el.scrollWidth <= el.clientWidth+2 && r.left >= a.left-1 && r.right <= a.right+1 && r.top >= a.top-1 && r.bottom <= a.bottom+1};
          }));
          check(measurements.length > 0 && measurements.every(x => x.fits), `${width}×${height} ${tab}按钮文字及边界无裁切`, measurements);
          await capture(page, `personnel-tab-${index+1}-${width}`);
        }
      });
      await section(page, 'fence-checkbox-' + width, async check => {
        await go(page, 'fences');
        const items = await page.locator('[data-form="fence"] label.row').evaluateAll(nodes => nodes.map(label => {
          const input = label.querySelector('input'), box = input.getBoundingClientRect();
          const lines = [...label.childNodes].filter(n => n.nodeType === Node.TEXT_NODE && n.textContent.trim()).flatMap(node => {
            const range = document.createRange(); range.selectNodeContents(node);
            return [...range.getClientRects()].map(r => Math.round(r.top));
          });
          return {text: label.textContent.trim(), width: box.width, height: box.height, lineCount: new Set(lines).size, scrollWidth: label.scrollWidth, clientWidth: label.clientWidth};
        }));
        check(items.length === 3 && items.every(x => x.width === 16 && x.height === 16 && x.lineCount === 1 && x.scrollWidth <= x.clientWidth+1), `${width}×${height}围栏复选框16px且标签单行`, items);
        await capture(page, 'fence-checkbox-' + width);
      });
      await section(page, 'overview-card-' + width, async check => {
        await go(page, 'overview');
        const value = await page.locator('.overview-bottom > .panel:first-child tbody tr:last-child .btn').evaluate(el => {
          const b = el.getBoundingClientRect(), p = el.closest('.panel').getBoundingClientRect();
          return {button: {left:b.left, right:b.right, top:b.top, bottom:b.bottom, height:b.height}, card: {left:p.left, right:p.right, top:p.top, bottom:p.bottom}, fits: b.left >= p.left && b.right <= p.right && b.top >= p.top && b.bottom <= p.bottom};
        });
        check(value.fits, `${width}×${height}总览末行查看监护按钮完整处于原卡片边界内`, value);
        await capture(page, 'overview-card-' + width);
      });
    }
    await section(page, 'screen-theme', async check => {
      await page.setViewportSize({width: 1672, height: 941});
      await go(page, 'screen');
      const panel = await colors(page.locator('.screen-panel').first());
      check(panel.background === '#50b1f9' && alphaNear(panel.backgroundAlpha, 0.12) && panel.border === '#83f6fd' && alphaNear(panel.borderAlpha, 0.5), '大屏面板保留12%蓝色卡片底及50%青色边框', panel);
      const title = await colors(page.locator('.screen-panel-title').first());
      check(title.backgroundAlpha === 0 && title.border === '#ffffff' && alphaNear(title.borderAlpha, 0.1), '大屏标题底透明且分隔线为10%白色', title);
      const metricFonts = await page.evaluate(() => ['.screen-stat strong', '.screen-stat .fraction', '.screen-ring strong', '.screen-metric strong'].map(selector => {
        const style = getComputedStyle(document.querySelector(selector));
        return {selector, size: style.fontSize, family: style.fontFamily};
      }));
      check(metricFonts.every((f, i) => f.size === ['50px', '43px', '41px', '30px'][i] && /^Arial/.test(f.family)), '大屏50/43/41/30px展示数字及Arial字体保持原样', metricFonts);
      await capture(page, 'screen-theme');
    });
    await section(page, 'empty-station', async check => {
      await page.setViewportSize({width: 1672, height: 941});
      await go(page, 'overview');
      const previousPeople = await page.evaluate(() => R.people().map(p => p.name));
      await page.getByRole('combobox', {name: '选择厂站'}).selectOption('S2');
      for (const name of ['overview', 'personnel', 'works', 'materials', 'location', 'alarms', 'statistics']) {
        await go(page, name);
        const data = await page.evaluate(() => ({station:R.s.station, people:R.people().length, works:R.works().length, events:R.events().length, materials:R.materials().length}));
        const visible = await page.locator('.main').innerText();
        check(data.station === 'S2' && !data.people && !data.works && !data.events && !data.materials && !previousPeople.some(name => visible.includes(name)), '空厂站 ' + name + ' 不残留上个厂站人员与关联记录', data);
        if (name === 'personnel') await capture(page, 'empty-personnel');
      }
    });
    await section(page, 'browser-health', async check => {
      check(!browserErrors.length, '浏览器无脚本错误', browserErrors);
      check(!failedRequests.length, '资源请求无失败', failedRequests);
    });
    const failed = results.filter(r => !r.passed);
    console.log(JSON.stringify({passed:results.length-failed.length, failed:failed.length, output}));
    assert.equal(failed.length, 0, failed.map(r => r.name).join(', '));
  } finally {
    if (browser) await browser.close();
    server.kill();
  }
})().catch(error => {console.error(error); process.exitCode = 1;});
