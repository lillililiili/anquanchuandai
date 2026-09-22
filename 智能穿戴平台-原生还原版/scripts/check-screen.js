// Pure display dashboard verification, isolated from the user's stored data.
async (page) => {
  const context = await page.context().browser().newContext({viewport: {width: 1672, height: 941}, deviceScaleFactor: 1});
  await context.addInitScript(() => {
    sessionStorage.setItem("rolling-session", "admin");
    sessionStorage.setItem("rolling-screen-v1", JSON.stringify({station: "S1", personId: "P4", personPaused: true}));
  });
  const p = await context.newPage(), errors = [], failures = [], checks = [];
  p.on("pageerror", err => errors.push(err.message));
  p.on("response", res => {if (res.status() >= 400) failures.push(res.url());});
  const assert = (value, message) => {if (!value) throw Error(message); checks.push(message);};
  const selected = () => p.locator(".screen-vital-data").getAttribute("data-person-id");
  const events = () => p.locator(".screen-event").evaluateAll(nodes => nodes.map(n => n.dataset.eventId).join(","));
  const videos = () => p.locator(".screen-video-tile").evaluateAll(nodes => nodes.map(n => n.dataset.personId).join(","));
  const controls = '.screen-stage button, .screen-stage a, .screen-stage select, .screen-stage input, .screen-stage textarea, .screen-stage [tabindex], .screen-stage [contenteditable], .screen-stage [data-screen-action], .screen-stage [role="button"], .screen-stage [role="link"]';
  try {
    await p.clock.install({time: new Date("2026-09-21T10:42:00+08:00")});
    await p.clock.pauseAt(new Date("2026-09-21T10:42:01+08:00"));
    await p.goto("http://127.0.0.1:5188/#/overview");
    await p.evaluate(() => {
      const set = window.setInterval, clear = window.clearInterval;
      window.screenTestIntervals = new Set();
      window.setInterval = (...args) => {const id = set(...args); window.screenTestIntervals.add(id); return id;};
      window.clearInterval = id => {window.screenTestIntervals.delete(id); return clear(id);};
    });
    await p.getByRole("link", {name: "数据大屏", exact: true}).click();
    await p.locator(".screen").waitFor();
    await p.evaluate(() => document.fonts.ready);
    await p.evaluate(() => Promise.all([...document.images].map(img => img.decode())));
    assert(await p.locator(controls).count() === 0, "大屏 DOM 无按钮、链接、下拉框或可聚焦操作入口");
    assert(!/上一|下一|暂停|返回系统|全屏|点击|预览/.test(await p.locator('.screen').innerText()), "无操作提示文字");
    assert(await selected() === "P1", "旧版暂停记录不影响纯展示模式");
    await p.locator('.screen-head').hover();
    assert(await p.locator(controls).count() === 0, "顶部悬停不出现隐藏工具栏");
    const initial = {person: await selected(), events: await events(), videos: await videos()};
    for (const selector of ['.screen-brand', '.screen-pin', '.screen-event', '.screen-video-tile', '[data-screen-person]']) await p.locator(selector).first().click();
    await p.keyboard.press('Tab'); await p.keyboard.press('Enter'); await p.keyboard.press('Space');
    assert(p.url().endsWith('#/screen') && await selected() === initial.person, "点击展示区域和键盘操作不会跳转或选人");
    assert(await p.locator('[role="dialog"]').count() === 0, "点击视频不打开预览弹窗");
    await p.mouse.move(1000, 910);
    await p.screenshot({path: "qa/screen/dashboard.png", animations: "disabled"});
    await p.clock.runFor(2900);
    assert(await selected() === initial.person && await events() === initial.events && await videos() === initial.videos, "三组轮播不早于 3 秒切换");
    await p.clock.runFor(200);
    assert(await selected() === "P2", "人员 3 秒自动切换");
    assert(await events() !== initial.events, "事件 3 秒自动轮播");
    assert(await videos() !== initial.videos, "视频 3 秒自动换组");
    assert(await p.locator('[data-screen-person]').textContent() === '李志远 · 锅炉区', "人员身份以静态文字同步更新");
    assert(await p.locator('[data-screen-trend]').getAttribute('data-person-id') === 'P2', "心率趋势联动当前人员");
    await p.clock.runFor(21000);
    assert(await selected() === 'P1', "8 人在 24 秒完成一轮");
    await p.evaluate(() => {const v = R.db.state.vitals.find(v => v.personId === 'P1'); v.heartRate = 81; v.observedAt = RollingData.DATE + ' 10:42:10';});
    await p.clock.runFor(2100);
    assert(await p.locator('[data-metric="0"]').textContent() === '81' && await p.locator('[data-person-time]').textContent() === '10:42:10', "纯展示模式持续刷新读数和采集时间");
    await p.evaluate(() => {R.db.device('RL-W002').online = false;});
    await p.clock.runFor(1000);
    assert(await selected() === 'P2' && await p.locator('[data-person-status]').textContent() === '离线', "自动轮播保留离线人员并显示状态");
    assert((await p.locator('[data-metric]').allTextContents()).every(x => x === '—'), "离线读数显示空值");
    await p.evaluate(() => {R.db.state.events.push({id: 'SCREEN-QA-ALERT', station: 'S1', date: RollingData.DATE, personId: 'P5', deviceId: 'RL-W005', type: '生命体征', title: '生命体征待核验', time: '10:42', status: '待认领'});});
    await p.clock.runFor(2100);
    assert(await selected() === 'P5', "新增异常自动插播对应人员");
    assert(await p.locator('.screen-alert').isVisible(), "异常关注信息持续展示");
    await p.clock.runFor(6100);
    assert(await p.locator('.screen-event').first().getAttribute('data-event-id') === 'SCREEN-QA-ALERT', "异常事件不随轮播消失");
    assert(await p.locator(controls).count() === 0, "异常和自动刷新后仍没有操作控件");
    await p.clock.resume();
    for (const [width, height] of [[1366, 768], [1920, 1080]]) {
      await p.setViewportSize({width, height});
      await p.waitForFunction(() => {const r = document.querySelector(".screen").getBoundingClientRect(); return r.left >= -1 && r.top >= -1 && r.right <= innerWidth + 1 && r.bottom <= innerHeight + 1;});
      assert(true, `${width}×${height} 等比适配无裁切`);
      if (width === 1366) await p.screenshot({path: 'qa/screen/dashboard-1366.png'});
    }
    await p.goBack(); await p.getByRole('combobox', {name: '选择厂站'}).waitFor();
    assert(await p.evaluate(() => window.screenTestIntervals.size) === 1, "浏览器后退正常返回且清理大屏定时器");
    await p.getByRole('combobox', {name: '选择厂站'}).selectOption('S2');
    await p.getByRole('link', {name: '数据大屏', exact: true}).click();
    assert(await p.locator('.screen-event').count() === 0 && await p.locator('.screen-video-tile').count() === 0, "空厂站不残留上一厂站数据");
    assert(await p.locator(controls).count() === 0, "空厂站也无操作入口");
    await p.screenshot({path: 'qa/screen/empty-station.png'});
    await p.reload(); await p.locator('.screen').waitFor();
    assert(await p.locator('.screen-station').textContent() === '北江示范电厂', "刷新保留厂站上下文");
    assert(errors.length === 0, "浏览器无脚本错误");
    assert(failures.length === 0, "素材请求无失败");
    return {checks, errors, failures};
  } finally {await context.close();}
}
