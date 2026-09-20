async (page) => {
  const origin = page.url().split('/').slice(0, 3).join('/'), checks = []
  const check = (ok, text) => { if (!ok) throw new Error(text); checks.push(text) }, button = name => page.getByRole('button', { name, exact: true })
  await page.reload(); await page.getByRole('button', { name: /^(用户菜单|进入系统)$/ }).first().waitFor()
  if (await button('用户菜单').count()) { await button('用户菜单').click(); await page.getByText('退出登录', { exact: true }).click() }
  await page.getByLabel('预置身份', { exact: true }).selectOption('owner'); await button('进入系统').click(); await button('用户菜单').waitFor()
  await page.goto(origin + '/#/video/device-1-1-helmet?siteId=mock-site-1'); await button('播放本地视频').waitFor()
  const media = page.getByLabel('本地视频画面', { exact: true })
  for (let n = 0; n < 3; n++) {
    await button('播放本地视频').click(); await page.locator('.video-tag').getByText('播放中', { exact: true }).waitFor()
    await button('暂停').click(); check(await media.evaluate(v => !v.getAttribute('src') && !v.srcObject), '重复暂停释放来源' + n)
  }
  await button('播放本地视频').click(); await page.locator('.video-tag').getByText('播放中', { exact: true }).waitFor()
  await button('开始预置录像').click(); await page.waitForTimeout(700); await button('停止录像').click(); await page.getByLabel('待保存媒体').waitFor()
  await page.getByLabel('当前厂站').selectOption('mock-site-2'); await button('继续查看').click()
  check(await page.getByLabel('待保存媒体').isVisible() && await page.getByLabel('当前厂站').inputValue() === 'mock-site-1', '未保存录像拒绝切站后保留')
  await button('丢弃').click(); check(!await page.getByLabel('待保存媒体').count(), '显式丢弃不生成资料')
  await page.evaluate(() => { Object.defineProperty(document, 'hidden', { configurable: true, value: true }); document.dispatchEvent(new Event('visibilitychange')) })
  check(await media.evaluate(v => !v.getAttribute('src')), '隐藏释放媒体')
  await page.evaluate(() => { delete document.hidden; document.dispatchEvent(new Event('visibilitychange')) })
  check(await media.evaluate(v => v.paused && !v.getAttribute('src')), '恢复不自动播放')
  await page.evaluate(async () => { const { saveScenario } = await import('/src/mock/storage.js'); saveScenario({ module: 'video', mode: 'failure' }) })
  await button('播放本地视频').click(); await button('重试本地播放').waitFor()
  check((await page.locator('.mock-monitor').innerText()).includes('播放失败'), '来源故障明确失败')
  await page.evaluate(async () => { const { saveScenario } = await import('/src/mock/storage.js'); saveScenario({ module: 'video', mode: 'normal' }) })
  await button('重试本地播放').click(); await page.locator('.video-tag').getByText('播放中', { exact: true }).waitFor(); check(true, '显式重试可恢复')
  await page.evaluate(async () => { const { expireSession } = await import('/src/mock/request.js'); expireSession() }); await button('进入系统').waitFor()
  check(!await page.locator('video').count(), '会话失效销毁播放器')
  await page.getByLabel('预置身份', { exact: true }).selectOption('reader'); await button('进入系统').click(); await button('用户菜单').waitFor()
  await page.goto(origin + '/#/video/device-1-1-helmet?siteId=mock-site-1'); await button('播放本地视频').waitFor()
  check(await button('预置抓拍').isDisabled() && await button('开始预置录像').isDisabled() && await button('本地隐私上报：开启').isDisabled(), '只读身份不能生成资料或本地隐私上报')
  return checks
}
