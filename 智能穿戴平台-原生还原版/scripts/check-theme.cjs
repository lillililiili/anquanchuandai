/* Visual inventory in a fresh browser context; never uses the user's profile. */
const fs = require('node:fs');
const path = require('node:path');
const { spawn } = require('node:child_process');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const phase = process.argv[2] || 'after';
assert(['before', 'after'].includes(phase));
const runtime = process.env.PLAYWRIGHT_MODULE || 'C:/Users/19221/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright';
const { chromium } = require(runtime);
const routes = ['login', 'overview', 'personnel', 'person/P1', 'works', 'work/GL-20260915-018', 'video', 'single/P1', 'materials', 'location', 'tracks/P1', 'fences', 'alarms', 'event/RL-E-0915-001', 'dispatch', 'sos', 'statistics', 'screen'];
const sizes = [[1672, 941], [1366, 768], [1920, 1080]];
const qaRoot = path.resolve(root, process.env.THEME_QA_DIR || 'qa/theme');
const output = path.join(qaRoot, phase);
const base = 'http://127.0.0.1:5208';
const server = spawn(process.execPath, [path.join(root, 'server.js'), '--port', '5208'], { windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
const ready = new Promise((resolve, reject) => {
  server.stdout.once('data', resolve);
  server.once('error', reject);
  server.once('exit', code => reject(Error('Preview server exited: ' + code)));
});
const fileName = route => route.replace(/\//g, '-');
async function settle(page) {
  await page.waitForFunction(() => window.R && document.querySelector('#app').children.length > 0);
  await page.evaluate(async () => {
    await document.fonts.ready;
    await Promise.all([...document.images].map(img => img.decode().catch(() => {})));
  });
  await page.waitForTimeout(100);
}
async function inventory(page) {
  return page.evaluate(() => {
    const rect = el => {
      const r = el.getBoundingClientRect();
      return {x: Math.round(r.x), y: Math.round(r.y), width: Math.round(r.width), height: Math.round(r.height)};
    };
    const selectors = ['.topbar', '.sidebar', '.main', '.screen', '.login-card'];
    const geometry = Object.fromEntries(selectors.filter(s => document.querySelector(s)).map(s => [s, rect(document.querySelector(s))]));
    const styles = [...document.querySelectorAll('.panel,.panel-title,.page-heading h1,.btn.primary,input:not([type=checkbox]),th,tbody tr,.modal')].slice(0, 50).map(el => {
      const s = getComputedStyle(el);
      return {tag: el.tagName, class: el.className, color: s.color, background: s.backgroundColor, border: s.borderColor, radius: s.borderRadius, fontSize: s.fontSize, height: Math.round(el.getBoundingClientRect().height)};
    });
    const controls = [...document.querySelectorAll('.btn,input,select,textarea')].filter(el => el.getClientRects().length);
    const clipped = controls.filter(el => el.scrollWidth > el.clientWidth + 3 && !['INPUT', 'TEXTAREA', 'SELECT'].includes(el.tagName)).map(el => ({text: el.textContent.trim(), width: el.clientWidth, scrollWidth: el.scrollWidth}));
    return {geometry, bodyWidth: document.documentElement.scrollWidth, viewportWidth: innerWidth, controls: controls.length, clipped, styles};
  });
}
(async () => {
  let browser;
  try {
    fs.mkdirSync(output, {recursive: true});
    await ready;
    browser = await chromium.launch({headless: true, executablePath: process.env.CHROME_PATH || 'C:/Program Files/Google/Chrome/Application/chrome.exe'});
    const context = await browser.newContext({viewport: {width: 1672, height: 941}, deviceScaleFactor: 1});
    const page = await context.newPage();
    const errors = [], failedRequests = [], result = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('response', response => { if (response.status() >= 400) failedRequests.push(response.url()); });
    await page.goto(base + '/#/login');
    for (const [width, height] of sizes) {
      await page.setViewportSize({width, height});
      for (const route of routes) {
        await page.evaluate(isLogin => {
          if (isLogin) sessionStorage.removeItem('rolling-session');
          else sessionStorage.setItem('rolling-session', 'admin');
        }, route === 'login');
        await page.goto(base + '/#/' + route);
        await page.evaluate(() => R.render());
        await settle(page);
        assert(page.url().endsWith('#/' + route), 'Route changed: ' + route);
        const metrics = await inventory(page);
        result.push({route, viewport: [width, height], ...metrics});
        if (width === 1672) await page.screenshot({path: path.join(output, fileName(route) + '.png'), fullPage: true, animations: 'disabled'});
        console.log(phase, width, route, 'width=' + metrics.bodyWidth, 'clipped=' + metrics.clipped.length);
      }
    }
    await page.setViewportSize({width: 1672, height: 941});
    await page.goto(base + '/#/person/P1');
    await settle(page);
    await page.locator('[data-action="vital-history"]').first().click();
    await page.locator('.modal').waitFor();
    await page.screenshot({path: path.join(output, 'vital-history-modal.png'), fullPage: true});
    await page.locator('[data-action="modal-close"]').last().click();
    await page.locator('[data-action="notifications"]').click();
    await page.screenshot({path: path.join(output, 'notifications-modal.png'), fullPage: true});
    const comparison = [];
    if (phase === 'after') {
      const baseline = JSON.parse(fs.readFileSync(path.join(qaRoot, 'before', 'inventory.json'), 'utf8'));
      for (const actual of result) {
        const previous = baseline.result.find(row => row.route === actual.route && row.viewport[0] === actual.viewport[0]);
        const label = actual.viewport[0] + ' ' + actual.route;
        comparison.push({label, noNewOverflow: actual.bodyWidth <= previous.bodyWidth, noClippedControls: actual.clipped.length <= previous.clipped.length});
        for (const selector of ['.topbar', '.sidebar', '.screen']) {
          if (previous.geometry[selector]) assert.deepEqual(actual.geometry[selector], previous.geometry[selector], label + ' changed ' + selector);
        }
        if (previous.geometry['.main']) {
          for (const key of ['x', 'y', 'width']) assert.equal(actual.geometry['.main'][key], previous.geometry['.main'][key], label + ' main ' + key);
        }
      }
    }
    fs.writeFileSync(path.join(output, 'inventory.json'), JSON.stringify({phase, errors, failedRequests, comparison, result}, null, 2));
    assert(comparison.every(row => row.noNewOverflow && row.noClippedControls), 'New overflow or clipped controls: ' + JSON.stringify(comparison.filter(row => !row.noNewOverflow || !row.noClippedControls)));
    assert.equal(errors.length, 0, errors.join('\n'));
    assert.equal(failedRequests.length, 0, failedRequests.join('\n'));
    console.log('Saved', result.length, 'page/viewport checks and 20 screenshots to', output);
  } finally {
    if (browser) await browser.close();
    server.kill();
  }
})().catch(error => {console.error(error); process.exitCode = 1;});
